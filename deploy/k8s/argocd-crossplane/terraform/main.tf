# Bootstrap layer for one Datagrok environment. Run it again with another
# tfvars file and state key for each additional environment.
#
# Terraform owns only what must exist before Kubernetes can manage the rest:
# the network, the EKS cluster, the IAM roles of the in-cluster controllers,
# and ArgoCD with one root Application. Everything else (Crossplane, RDS, S3,
# the Datagrok chart) is synced by ArgoCD from the config repo.
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
  name = "datagrok-${var.env}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)
}

# --- Network ----------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

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

# --- Cluster ----------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

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
}

# --- IAM roles of the in-cluster controllers (IRSA) -------------------------

# Crossplane AWS providers. Every Upbound provider pod gets its own generated
# ServiceAccount (upbound-provider-aws-<svc>-<hash>), hence the wildcard.
data "aws_iam_policy_document" "crossplane_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:crossplane-system:upbound-provider-aws-*"]
    }
  }
}

# Scoped to this environment's resources: the datagrok-<env> RDS instance,
# bucket, log group and app role. A provider in one environment cannot touch another.
data "aws_iam_policy_document" "crossplane" {
  statement {
    sid       = "Rds"
    actions   = ["rds:*"]
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
    sid       = "SecurityGroups"
    actions   = ["ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress",
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
    sid       = "Iam"
    actions   = ["iam:*Role", "iam:*RolePolicy", "iam:*RolePolicies", "iam:TagRole", "iam:UntagRole",
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

  role_name                              = "${local.name}-lb-controller"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# External Secrets reads and writes datagrok/<env> (the PushSecret seeds it).
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${local.name}-external-secrets"
  role_policy_arns = { secrets = aws_iam_policy.external_secrets.arn }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name = "${local.name}-external-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:CreateSecret",
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
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
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
            valuesObject = {
              env = var.env
              repo = { url = var.config_repo_url, revision = var.config_repo_revision }
              aws = {
                accountId           = data.aws_caller_identity.current.account_id
                region              = var.region
                vpcId               = module.vpc.vpc_id
                vpcCidr             = var.vpc_cidr
                dbSubnetGroup       = module.vpc.database_subnet_group_name
                nodeSecurityGroupId = module.eks.node_security_group_id
                oidcProvider        = module.eks.oidc_provider
                clusterName         = module.eks.cluster_name
                crossplaneRoleArn   = aws_iam_role.crossplane.arn
                lbControllerRoleArn = module.lb_controller_irsa.iam_role_arn
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
