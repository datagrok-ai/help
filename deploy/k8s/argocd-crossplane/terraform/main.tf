# Bootstrap layer for one Datagrok environment. Run it again with another
# tfvars file and state key for each additional environment.
#
# Terraform owns only what must exist before Kubernetes can manage the rest:
# the network, the EKS cluster, the IAM roles of the in-cluster controllers,
# and ArgoCD with one root Application. Everything else (Crossplane, RDS, S3,
# the Datagrok chart) is synced by ArgoCD from the config repo.
#
# The VPC and the cluster can also be ones you already run: set existing_vpc_id
# (a new cluster in your VPC) or existing_cluster_name (your cluster and its VPC).
#
# Run once per environment with its own state:
#   terraform init -backend-config=env/main.backend.hcl
#   terraform apply -var-file=env/main.tfvars

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.80" }
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Service = "Datagrok", Environment = var.env, ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

locals {
  name                 = "datagrok-${var.env}"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 3)
  use_existing_cluster = var.existing_cluster_name != ""
  use_existing_vpc     = local.use_existing_cluster || var.existing_vpc_id != ""
}

resource "terraform_data" "inputs" {
  lifecycle {
    precondition {
      condition     = !local.use_existing_vpc || length(var.db_subnet_ids) >= 2
      error_message = "With an existing VPC or cluster, set db_subnet_ids to at least two private subnets in different availability zones for RDS."
    }
    precondition {
      condition     = local.use_existing_cluster || var.existing_vpc_id == "" || length(var.existing_private_subnet_ids) >= 2
      error_message = "With existing_vpc_id, set existing_private_subnet_ids to the private subnets for the cluster nodes (at least two, with a route to a NAT gateway)."
    }
  }
}

# --- Network ----------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"
  count   = local.use_existing_vpc ? 0 : 1

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  database_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 52 + i)]

  create_database_subnet_group = true
  database_subnet_group_name   = local.name

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

data "aws_vpc" "existing" {
  count = local.use_existing_vpc ? 1 : 0
  id    = local.use_existing_cluster ? data.aws_eks_cluster.existing[0].vpc_config[0].vpc_id : var.existing_vpc_id
}

# In your own VPC, RDS goes into the subnets you name.
resource "aws_db_subnet_group" "existing_vpc" {
  count      = local.use_existing_vpc ? 1 : 0
  name       = local.name
  subnet_ids = var.db_subnet_ids
  depends_on = [terraform_data.inputs]
}

# --- Cluster ----------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"
  count   = local.use_existing_cluster ? 0 : 1

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id     = local.vpc_id
  subnet_ids = local.use_existing_vpc ? var.existing_private_subnet_ids : module.vpc[0].private_subnets

  cluster_endpoint_public_access           = true
  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    general = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_min_size
      disk_size      = 100
    }
  }

  depends_on = [terraform_data.inputs]
}

data "aws_eks_cluster" "existing" {
  count = local.use_existing_cluster ? 1 : 0
  name  = var.existing_cluster_name
}

# IRSA needs the cluster's IAM OIDC provider. Terraform reads it; it doesn't create it.
data "aws_iam_openid_connect_provider" "existing" {
  count = local.use_existing_cluster ? 1 : 0
  url   = data.aws_eks_cluster.existing[0].identity[0].oidc[0].issuer
}

# The facts the rest of the stack needs, from whichever VPC and cluster are used.
locals {
  vpc_id           = local.use_existing_vpc ? data.aws_vpc.existing[0].id : module.vpc[0].vpc_id
  vpc_cidr         = local.use_existing_vpc ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
  db_subnet_group  = local.use_existing_vpc ? aws_db_subnet_group.existing_vpc[0].name : module.vpc[0].database_subnet_group_name
  cluster_name     = local.use_existing_cluster ? var.existing_cluster_name : module.eks[0].cluster_name
  cluster_endpoint = local.use_existing_cluster ? data.aws_eks_cluster.existing[0].endpoint : module.eks[0].cluster_endpoint
  cluster_ca       = local.use_existing_cluster ? data.aws_eks_cluster.existing[0].certificate_authority[0].data : module.eks[0].cluster_certificate_authority_data
  oidc_provider_arn = (local.use_existing_cluster ? data.aws_iam_openid_connect_provider.existing[0].arn
  : module.eks[0].oidc_provider_arn)
  oidc_provider = (local.use_existing_cluster ? replace(data.aws_eks_cluster.existing[0].identity[0].oidc[0].issuer, "https://", "")
  : module.eks[0].oidc_provider)
  # RDS accepts connections from this group. Managed node groups of an existing
  # cluster use the cluster security group unless you name another one.
  node_security_group_id = (local.use_existing_cluster
    ? coalesce(var.existing_node_security_group_id, data.aws_eks_cluster.existing[0].vpc_config[0].cluster_security_group_id)
  : module.eks[0].node_security_group_id)
}

# --- IAM roles of the in-cluster controllers (IRSA) -------------------------

# Crossplane AWS providers. Every Upbound provider pod gets its own generated
# ServiceAccount (upbound-provider-aws-<svc>-<hash>), hence the wildcard.
data "aws_iam_policy_document" "crossplane_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:crossplane-system:upbound-provider-aws-*"]
    }
  }
}

# Scoped to this environment's resources: the datagrok-<env> RDS instance,
# bucket, log group and app role. A provider in one environment cannot touch another.
data "aws_iam_policy_document" "crossplane" {
  statement {
    sid     = "Rds"
    actions = ["rds:*"]
    resources = [
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${local.name}",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:subgrp:${local.name}",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot:${local.name}-*",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:pg:*",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:og:*",
    ]
  }
  statement {
    sid       = "RdsDescribe"
    actions   = ["rds:Describe*", "rds:ListTagsForResource"]
    resources = ["*"]
  }
  statement {
    sid       = "S3"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.name}", "arn:aws:s3:::${local.name}-*"]
  }
  statement {
    sid = "SecurityGroups"
    actions = ["ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress", "ec2:CreateTags", "ec2:DeleteTags",
    "ec2:ModifySecurityGroupRules"]
    resources = ["*"]
  }
  statement {
    sid       = "Ec2Describe"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
  statement {
    sid = "Iam"
    actions = ["iam:*Role", "iam:*RolePolicy", "iam:*RolePolicies", "iam:TagRole", "iam:UntagRole",
    "iam:ListRoleTags", "iam:ListInstanceProfilesForRole", "iam:ListAttachedRolePolicies"]
    # Only the app role. A wider glob would let Crossplane edit its own role.
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-app"]
  }
  statement {
    sid       = "RdsServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["rds.amazonaws.com"]
    }
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/datagrok/${var.env}*"]
  }
  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups", "logs:ListTagsForResource"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "crossplane" {
  name               = "${local.name}-crossplane"
  assume_role_policy = data.aws_iam_policy_document.crossplane_trust.json
}

resource "aws_iam_role_policy" "crossplane" {
  name   = "manage-environment"
  role   = aws_iam_role.crossplane.id
  policy = data.aws_iam_policy_document.crossplane.json
}

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"
  count   = var.install_lb_controller ? 1 : 0

  role_name                              = "${local.name}-lb-controller"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# External Secrets reads and writes datagrok/<env> (the PushSecret seeds it).
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name        = "${local.name}-external-secrets"
  role_policy_arns = { secrets = aws_iam_policy.external_secrets.arn }
  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name = "${local.name}-external-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:TagResource",
        "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy"]
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:datagrok/${var.env}*"
    }]
  })
}

# --- ArgoCD and the root Application ----------------------------------------

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/argocd-values.yaml")]
}

# The only Application Terraform creates. It renders gitops/bootstrap with the
# cluster facts below; that chart creates every other Application.
resource "helm_release" "root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"
  namespace  = "argocd"
  depends_on = [helm_release.argocd]

  values = [yamlencode({
    applications = {
      bootstrap = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.config_repo_url
          targetRevision = var.config_repo_revision
          path           = "gitops/bootstrap"
          helm = {
            # datagrok.version: the environment file is the one place a release changes.
            valueFiles = ["../envs/${var.env}.yaml"]
            valuesObject = {
              env  = var.env
              repo = { url = var.config_repo_url, revision = var.config_repo_revision }
              controllers = {
                awsLoadBalancerController = var.install_lb_controller
              }
              aws = {
                accountId              = data.aws_caller_identity.current.account_id
                region                 = var.region
                vpcId                  = local.vpc_id
                vpcCidr                = local.vpc_cidr
                dbSubnetGroup          = local.db_subnet_group
                nodeSecurityGroupId    = local.node_security_group_id
                oidcProvider           = local.oidc_provider
                clusterName            = local.cluster_name
                crossplaneRoleArn      = aws_iam_role.crossplane.arn
                lbControllerRoleArn    = var.install_lb_controller ? module.lb_controller_irsa[0].iam_role_arn : ""
                externalSecretsRoleArn = module.external_secrets_irsa.iam_role_arn
              }
            }
          }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["ServerSideApply=true"]
        }
      }
    }
  })]
}
