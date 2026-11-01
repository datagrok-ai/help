---
title: "GitOps on EKS with ArgoCD and Crossplane"
sidebar_label: "ArgoCD and Crossplane (GitOps)"
sidebar_position: 6
description: Run Datagrok on EKS from a Git repository. Terraform builds the cluster and installs ArgoCD, and ArgoCD creates RDS, S3, and IAM through Crossplane and deploys the Helm chart.
keywords:
  - gitops
  - argocd
  - crossplane
  - terraform
  - eks
  - helm chart
  - infrastructure as code
---

This page describes how to run Datagrok on Amazon EKS, with all infrastructure and the application described in a Git repository and kept in
sync by ArgoCD. It complements the other paths in [Deployment](../deploy.md): use it when you want
every change, to the application or to AWS, to be a reviewed pull request.

The approach has three layers:

| Layer | Tool | Owns | Changes |
|-------|------|------|---------|
| Bootstrap | Terraform | VPC, EKS, node groups, IAM roles of the in-cluster controllers, ArgoCD, and one root Application | When a cluster is created or resized |
| Delivery | ArgoCD, in each cluster | Crossplane, External Secrets, AWS Load Balancer Controller, and the Datagrok [Helm chart](install-helm-chart.md) | Every pull request to the config repo |
| AWS resources | Crossplane, in each cluster | RDS, S3, the application IAM role, and the CloudWatch log group | Every pull request to the config repo |

After the bootstrap, Terraform steps back. Releases, database and bucket changes, and new settings
are commits to the config repo. Each cluster manages only its own environment, so there's no
central management cluster that can change all of them.

:::tip Ready-made templates

The [argocd-crossplane](https://github.com/datagrok-ai/help/tree/master/deploy/k8s/argocd-crossplane)
folder contains a complete config repo: Terraform, the ArgoCD applications, the Crossplane
composition, and the environment chart. The examples on this page are excerpts from it. The same
pattern runs Datagrok's own hosted instances.

:::

## Prerequisites

* An AWS account and an IAM principal that can create VPC, EKS, and IAM resources
* Terraform 1.6+ (or OpenTofu), Helm 3.8+, `kubectl`, and the AWS CLI
* A Git repository for the configuration, with a read-only deploy key for ArgoCD
* An S3 bucket for the Terraform state
* An issued ACM certificate for each environment's hostname, or a wildcard certificate

## Repository layout

```text
terraform/                    # bootstrap, one state per environment
  main.tf  variables.tf  outputs.tf
  argocd-values.yaml          # ArgoCD settings, including the health check for the environment
  env/main.tfvars
gitops/
  bootstrap/                  # app of apps, rendered with the facts Terraform passes in
  platform/                   # Crossplane providers, functions, XRD, and composition
  charts/datagrok-env/        # one environment: AWS resources, secrets, Datagrok chart
  envs/
    main.yaml                 # one file per environment
```

The templates define one environment, `main`. Its `envs/main.yaml` file is the only
environment-specific configuration. To run more environments, for example a staging copy, see
[Add an environment](#add-an-environment). Everything else is shared, so every environment gets
identical infrastructure.

## How the layers connect

1. Terraform creates the cluster, then installs ArgoCD and a root Application that points at
   `gitops/bootstrap`. It passes the cluster facts (account, region, VPC, database subnet group,
   node security group, OIDC provider, and controller role ARNs) as Helm values of that Application.
2. The bootstrap chart creates the other Applications in sync waves: the controllers first, then the
   Crossplane platform, then the environment.
3. The environment chart creates a `DatagrokEnvironment` resource. Crossplane expands it into the
   AWS resources through the composition.
4. ArgoCD waits until the `DatagrokEnvironment` reports `Ready`, then creates the database admin role
   and deploys the Datagrok chart.

No AWS credentials are stored in the cluster or in Git. Every controller, and Datagrok itself, uses
IAM Roles for Service Accounts (IRSA). Generated passwords are kept in AWS Secrets Manager.

## Bootstrap with Terraform

Terraform installs ArgoCD and creates the root Application with the cluster facts:

```hcl title="terraform/main.tf (excerpt)"
resource "helm_release" "root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      bootstrap = {
        source = {
          repoURL = var.config_repo_url
          path    = "gitops/bootstrap"
          helm = { valuesObject = {
            env = var.env
            aws = {
              region            = var.region
              vpcId             = module.vpc.vpc_id
              dbSubnetGroup     = module.vpc.database_subnet_group_name
              oidcProvider      = module.eks.oidc_provider
              crossplaneRoleArn = aws_iam_role.crossplane.arn
              # ...
            }
          } }
        }
        # ...
      }
    }
  })]
}
```

The Crossplane role is limited to the resources of its own environment: the `datagrok-<env>` RDS
instance, bucket, log group, and application role. A provider in one environment can't change another.

## Crossplane composition

The composite resource exposes only what differs between deployments. The composition turns it into
about a dozen AWS resources:

```yaml title="gitops/platform/xrd.yaml (excerpt)"
db:
  properties:
    instanceClass: {type: string, default: db.m7g.large}
    engineVersion: {type: string, default: "17.9"}
    multiAz: {type: boolean, default: true}
    deletionProtection: {type: boolean, default: true}
    backupRetentionDays: {type: integer, default: 35}
```

| Composed resource | Purpose |
|-------------------|---------|
| RDS instance and security group | PostgreSQL, encrypted, Multi-AZ, IAM authentication enabled, reachable only from the cluster nodes |
| S3 bucket | Versioned, encrypted, no public access, old versions expire after `storage.noncurrentVersionDays` |
| IAM role and policy | Assumed by the `datagrok` ServiceAccount. Grants S3 on the bucket, `rds-db:connect`, writing to the log group, and server keys in Secrets Manager |
| CloudWatch log group | `/datagrok/<env>`, where Datagrok exports audit, usage, and error logs |

## Environment files

An environment file sets the name, hostname, and version. A release is a pull request that changes
two lines:

```yaml title="gitops/envs/main.yaml"
env: main
hostname: datagrok.example.com
datagrok:
  chartVersion: 1.27.6-helm
  imageTag: 1.27.6
db:
  host: datagrok-main.abcdefghijkl.us-east-1.rds.amazonaws.com
```

Any value of the Datagrok Helm chart can be overridden per environment under `appValues`. See
`gitops/charts/datagrok-env/values.yaml` for the full contract.

## Deploy an environment

1. Push the `gitops/` folder to your config repo and set `config_repo_url` in
   `terraform/env/<env>.tfvars`.
1. Create the cluster and ArgoCD:

   ```bash
   cd terraform
   terraform init -backend-config="bucket=<state-bucket>" -backend-config="key=datagrok/main.tfstate" \
     -backend-config="region=us-east-1"
   terraform apply -var-file=env/main.tfvars
   ```

1. Give ArgoCD read access to the config repo:

   ```bash
   aws eks update-kubeconfig --name datagrok-main --region us-east-1
   kubectl -n argocd create secret generic config-repo \
     --from-literal=type=git --from-literal=url=git@github.com:acme/datagrok-config.git \
     --from-file=sshPrivateKey=./deploy-key
   kubectl -n argocd label secret config-repo argocd.argoproj.io/secret-type=repository
   ```

1. Wait for the AWS resources. RDS takes 10 to 15 minutes on first creation:

   ```bash
   kubectl get datagrokenvironment
   ```

1. Copy the `ENDPOINT` column into `db.host` in `gitops/envs/<env>.yaml` and push. ArgoCD creates
   the database admin role and deploys Datagrok.
1. Point the hostname's DNS record at the load balancer shown by
   `kubectl -n datagrok-<env> get ingress`.

The endpoint is set by hand only once per environment. It doesn't change afterwards.

## Day-to-day operations

| Task | How |
|------|-----|
| Release to an environment | Pull request that changes `chartVersion` and `imageTag` in `envs/<env>.yaml` |
| Roll back | Revert the pull request |
| Follow `bleeding-edge` | Set `imageTag: bleeding-edge`. A scheduled job resolves the tag to its digest and commits it to `datagrok.imageDigest` |
| Change RDS or S3 settings | Pull request to the composition or the environment file |
| Preview a change | `terraform plan` for the cluster. `argocd app diff` and `crossplane render` for Applications and AWS resources |

To resolve the current `bleeding-edge` digest for the refresh job:

```bash
docker buildx imagetools inspect datagrok/datagrok:bleeding-edge --format '{{.Manifest.Digest}}'
```

## Safeguards

Crossplane has no plan step that asks AWS what a change will do. A preview shows which fields change,
not whether AWS modifies, restarts, or replaces a resource. The templates protect data against that:

* RDS has deletion protection and takes a final snapshot. Removing the `DatagrokEnvironment` doesn't
  delete the database.
* The bucket isn't force-destroyed, so a non-empty bucket can't be deleted.
* Generated passwords are created once and kept in Secrets Manager under `datagrok/<env>`. Neither
  ArgoCD nor a resync regenerates them.
* Provider and chart versions are pinned. If you run a second environment, upgrade it first.

## Add an environment

Each environment gets its own cluster, ArgoCD, and AWS resources, built from the same templates:

1. Copy `terraform/env/main.tfvars` to `terraform/env/<env>.tfvars`. Set `env` and a VPC CIDR that
   doesn't overlap with other environments.
1. Copy `gitops/envs/main.yaml` to `gitops/envs/<env>.yaml`. Set `env`, `hostname`, and the version.
1. Run the [deploy steps](#deploy-an-environment) with the new file and a new state key, for example
   `key=datagrok/<env>.tfstate`.

Changes to the composition or the environment chart reach every environment. To try a change on one
environment first, point its root Application at a branch with `config_repo_revision`.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `platform` Application is `OutOfSync` on first deploy | Normal for a few minutes. Crossplane installs CRDs asynchronously, and the Application retries until they exist |
| `DatagrokEnvironment` stays not `Ready` | `kubectl describe datagrokenvironment` and `kubectl get managed` show the AWS error for each resource |
| AWS API returns `AccessDenied` | The Crossplane role policy in `terraform/main.tf` is scoped to `datagrok-<env>` names. A renamed resource needs the policy updated |
| Datagrok can't connect to the database | `db.host` in the environment file must match the RDS endpoint, and the `datagrok-db-bootstrap` job must have completed |

## See also

* [Install Datagrok with Helm](install-helm-chart.md)
* [AWS CloudFormation (EKS)](../aws/deploy-amazon-eks.mdx)
* [Images and versions](../images.md)
