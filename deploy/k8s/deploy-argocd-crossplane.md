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
folder contains a complete config repo: Terraform, the ArgoCD applications, and an environment
file. The parts that every installation shares, the environment chart and the Crossplane
composition, are published by Datagrok with each release, so your repo refers to them by version
instead of copying them. The examples on this page are excerpts from the folder.

:::

## Published packages

Datagrok publishes three artifacts on Docker Hub for every release. They always have the same
version:

| Artifact | Contents |
|----------|----------|
| `oci://registry-1.docker.io/datagrok/datagrok`, tag `<version>-helm` | The Datagrok [Helm chart](install-helm-chart.md). It shares the repository with the `datagrok/datagrok` image, and the `-helm` suffix keeps chart and image tags apart |
| `oci://registry-1.docker.io/datagrok/datagrok-env`, tag `<version>` | The environment chart. From an environment file it creates the AWS resources, the secrets, and an ArgoCD Application that deploys the Datagrok chart of the same version |
| `registry-1.docker.io/datagrok/crossplane-aws`, tag `<version>` | A Crossplane package with the `DatagrokEnvironment` API and the composition that turns it into AWS resources |

The environment file names one version, for example `1.28.0`, and that selects all three.

:::note

Release versions of `datagrok-env` and `crossplane-aws` are published starting with the first
Datagrok release after November 2026. Until then, use `0.0.3-bleeding-edge`, which is rebuilt from
the development branch every day.

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
  platform/                   # Crossplane providers and functions, with their versions
  envs/
    main.yaml                 # one file per environment
  charts/datagrok-env/        # source of the published environment chart
  crossplane-aws/             # source of the published Crossplane package
```

Your config repo needs `terraform/` and the first three `gitops/` folders. The last two are the
sources Datagrok publishes the packages from. Keep them only if you
[modify the environment chart or the composition](#modify-the-environment-chart-or-the-composition).

The templates define one environment, `main`. Its `envs/main.yaml` file is the only
environment-specific configuration. To run more environments, for example a staging copy, see
[Add an environment](#add-an-environment).

## How the layers connect

1. Terraform creates the cluster, then installs ArgoCD and a root Application that points at
   `gitops/bootstrap`. It passes the cluster facts (account, region, VPC, database subnet group,
   node security group, OIDC provider, and controller role ARNs) and the environment file as Helm
   values of that Application.
2. The bootstrap chart creates the other Applications in sync waves: the controllers first, then the
   Crossplane providers, functions, and the `crossplane-aws` package, then the environment from the
   `datagrok-env` chart.
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
          helm = {
            valueFiles = ["../envs/${var.env}.yaml"]
            valuesObject = {
              env = var.env
              aws = {
                region            = var.region
                vpcId             = module.vpc.vpc_id
                dbSubnetGroup     = module.vpc.database_subnet_group_name
                oidcProvider      = module.eks.oidc_provider
                crossplaneRoleArn = aws_iam_role.crossplane.arn
                # ...
              }
            }
          }
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

```yaml title="gitops/crossplane-aws/xrd.yaml (excerpt)"
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

The bootstrap chart installs the composition as the `crossplane-aws` package of the environment's
version. The providers and functions it uses are installed from `gitops/platform`, with the versions
the package was built against.

## Environment files

An environment file sets the name, hostname, and version. A release is a pull request that changes
one line:

```yaml title="gitops/envs/main.yaml"
env: main
hostname: datagrok.example.com
datagrok:
  version: 1.28.0
db:
  host: datagrok-main.abcdefghijkl.us-east-1.rds.amazonaws.com
```

The rest of the file is optional. See [Customize the installation](#customize-the-installation).

## Deploy an environment

1. Push the `terraform/` and `gitops/` folders to your config repo and set `config_repo_url` in
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

## Customize the installation

Most changes are values in the environment file. They survive upgrades: a new `datagrok.version`
brings a new chart and composition, and your values are applied on top of them. The full list of
environment file values, with their defaults, is in
[`charts/datagrok-env/values.yaml`](https://github.com/datagrok-ai/help/tree/master/deploy/k8s/argocd-crossplane/gitops/charts/datagrok-env/values.yaml).

### AWS resources

| Value | Default | Description |
|-------|---------|-------------|
| `db.instanceClass` | `db.m7g.large` | RDS instance class |
| `db.engineVersion` | `17.9` | PostgreSQL version |
| `db.allocatedStorage`, `db.maxAllocatedStorage` | `100`, `500` | Initial storage and the storage autoscaling limit, in GB |
| `db.multiAz` | `true` | Standby instance in a second availability zone |
| `db.backupRetentionDays` | `35` | Days of automated RDS backups |
| `db.deletionProtection`, `db.skipFinalSnapshot` | `true`, `false` | Keep them for production. See [Safeguards](#safeguards) |
| `storage.noncurrentVersionDays` | `30` | Days S3 keeps overwritten and deleted file versions |
| `logging.retentionDays` | `365` | Retention of the CloudWatch log group |
| `ingress.certificateArn` | empty | ACM certificate for the load balancer. Empty: the controller finds an issued certificate that matches `hostname` |

A smaller, cheaper environment, for example for evaluation:

```yaml title="gitops/envs/eval.yaml"
env: eval
hostname: datagrok-eval.example.com
datagrok:
  version: 1.28.0
db:
  instanceClass: db.t4g.medium
  multiAz: false
  backupRetentionDays: 7
```

Changing the instance class or storage of an existing database makes AWS modify the instance, which
can restart it. Change it in a maintenance window.

### Datagrok settings

Any value of the [Datagrok Helm chart](install-helm-chart.md) can be set under `appValues`. It's
merged over the values the environment chart computes, so it also overrides them. For example,
single sign-on, more resources for the server, and the extended database connectors:

```yaml title="gitops/envs/main.yaml (excerpt)"
appValues:
  datagrok:
    openId:
      enabled: true
      configEndpoint: https://login.example.com/.well-known/openid-configuration
      clientId: datagrok
    resources:
      requests: {cpu: "4", memory: 8Gi}
      limits: {cpu: "8", memory: 16Gi}
  grokConnectExtended:
    enabled: true
```

The values that connect Datagrok to the AWS resources, such as `postgres.external.host`,
`storage.s3.bucket`, and the ServiceAccount role, are computed from the environment. Override them
only if you replace the resources they point to.

### Service versions

`datagrok.version` deploys the Datagrok Helm chart of that release, and every service runs the image
version that chart sets by default (see [Images and versions](../images.md)). To run another
version of a service, for example a fix built for you or a connector update, pin it under `images`
with a tag or a `sha256:` digest:

```yaml title="gitops/envs/main.yaml (excerpt)"
datagrok:
  version: 1.28.0
images:
  datagrok: 1.28.1
  grokConnect: 2.8.7
  # A digest pins one build, also of a moving tag such as bleeding-edge
  grokPipe: sha256:3f1c...
```

| Key | Service |
|-----|---------|
| `datagrok` | Datagrok server and web application |
| `grokConnect` | Database connectors (JDBC) |
| `grokConnectAdbc` | Database connectors (ADBC) |
| `grokConnectExtended` | Amazon Neptune and Cloudera Impala connectors |
| `grokPipe` | Streaming proxy |
| `spawner` | Starts the containers of Datagrok packages |
| `rabbitmq` | Message queue |

A service that isn't listed follows the chart, so it moves to the new default with every release.
A pinned service stays on its version until you change or remove the pin. A key that isn't in the
table fails the sync with the list of valid keys.

To run a different Datagrok chart than the release, set `datagrok.chartVersion`, for example
`1.28.1-helm`.

### Cluster

The cluster is set by the Terraform variables in `terraform/env/<env>.tfvars` and changes with
`terraform apply`:

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `vpc_cidr` | `10.0.0.0/16` | Address range of the new VPC. It must not overlap with other environments you connect to |
| `kubernetes_version` | `1.33` | EKS version |
| `node_instance_types` | `["m6i.xlarge"]` | Instance types of the node group |
| `node_min_size`, `node_max_size` | `2`, `5` | Node group size limits |
| `config_repo_revision` | `main` | Branch or tag of the config repo that ArgoCD syncs |

### Modify the environment chart or the composition

If values aren't enough, you can deploy your own copy of the environment chart, the composition, or
both. With a copy, you merge the changes of each new release into it yourself, so prefer values
where they work.

1. Keep `gitops/charts/datagrok-env/` or `gitops/crossplane-aws/`, from the template folder of the
   release you run, in your config repo, and change them there.
1. Tell the bootstrap chart to use them, in the environment file:

   ```yaml title="gitops/envs/main.yaml (excerpt)"
   datagrok:
     version: 1.28.0
     # Deploy the environment chart from this repo instead of the published one
     envChartPath: gitops/charts/datagrok-env
     chartVersion: 1.28.0-helm   # a chart from Git has no release default
     # Don't install the crossplane-aws package
     crossplanePackage: false
   ```

1. With `crossplanePackage: false`, move `xrd.yaml` and `composition.yaml` into `gitops/platform/`,
   which ArgoCD applies as they are.

A composition that creates resources with other names needs the Crossplane role policy in
`terraform/main.tf` updated, because the policy only allows `datagrok-<env>` names.

## Day-to-day operations

| Task | How |
|------|-----|
| Release to an environment | Pull request that changes `datagrok.version` in `envs/<env>.yaml` |
| Roll back | Revert the pull request |
| Follow `bleeding-edge` | Set `datagrok.version: 0.0.3-bleeding-edge`. The `bleeding-edge` image tag moves with every build. To roll out each build as a recorded change, a scheduled job resolves the tag to its digest and commits it to `images.datagrok` |
| Change RDS or S3 settings | Pull request to the environment file |
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
* Every version is pinned: the Datagrok release by `datagrok.version`, and the providers,
  functions, and controllers in `gitops/platform` and `gitops/bootstrap`. If you run a second
  environment, upgrade it first.

## Add an environment

Each environment gets its own cluster, ArgoCD, and AWS resources, built from the same templates:

1. Copy `terraform/env/main.tfvars` to `terraform/env/<env>.tfvars`. Set `env` and a VPC CIDR that
   doesn't overlap with other environments.
1. Copy `gitops/envs/main.yaml` to `gitops/envs/<env>.yaml`. Set `env`, `hostname`, and the version.
1. Run the [deploy steps](#deploy-an-environment) with the new file and a new state key, for example
   `key=datagrok/<env>.tfstate`.

Each environment has its own `datagrok.version`, so you can release to one environment first.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `platform` Application is `OutOfSync` on first deploy | Normal for a few minutes. Crossplane installs CRDs asynchronously, and the Application retries until they exist |
| `DatagrokEnvironment` kind is unknown | `kubectl get configuration datagrok-aws` shows whether the `crossplane-aws` package installed. A version that isn't published fails to pull |
| `DatagrokEnvironment` stays not `Ready` | `kubectl describe datagrokenvironment` and `kubectl get managed` show the AWS error for each resource |
| AWS API returns `AccessDenied` | The Crossplane role policy in `terraform/main.tf` is scoped to `datagrok-<env>` names. A renamed resource needs the policy updated |
| Datagrok can't connect to the database | `db.host` in the environment file must match the RDS endpoint, and the `datagrok-db-bootstrap` job must have completed |

## See also

* [Install Datagrok with Helm](install-helm-chart.md)
* [AWS CloudFormation (EKS)](../aws/deploy-amazon-eks.mdx)
* [Images and versions](../images.md)
