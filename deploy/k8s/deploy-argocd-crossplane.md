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
| Bootstrap | Terraform | VPC, EKS, and node groups, or [your existing ones](#existing-vpc-or-eks-cluster), plus IAM roles of the in-cluster controllers, ArgoCD, and one root Application | When a cluster is created or resized |
| Delivery | ArgoCD, in each cluster | Crossplane, External Secrets, AWS Load Balancer Controller, and the Datagrok [Helm chart](install-helm-chart.md) | Every pull request to the config repo |
| AWS resources | Crossplane, in each cluster | RDS, S3, the application IAM role, and the CloudWatch log group | Every pull request to the config repo |

After the bootstrap, Terraform steps back. Releases, database and bucket changes, and new settings
are commits to the config repo. Each cluster manages only its own environment, so there's no
central management cluster that can change all of them.

:::info Which AWS path?

The [AWS CloudFormation (EKS)](../aws/deploy-amazon-eks.mdx) template builds a similar stack (EKS,
RDS, S3, IAM roles with IRSA, a load balancer, and the Helm chart) as one CloudFormation stack that
you update in the AWS console. Choose the GitOps templates on this page when every change should be
a reviewed pull request, or when you run several environments from the same templates.

Both can create the VPC and the cluster or use ones you already run: see
[Existing VPC or EKS cluster](#existing-vpc-or-eks-cluster) here, and
[New or existing cluster](../aws/deploy-amazon-eks.mdx#new-or-existing-cluster) for CloudFormation. If
your database and storage exist too, [install the Helm chart](install-helm-chart.md) directly. To move
an existing stack on [ECS](../aws/deploy-amazon-ecs.mdx) to EKS, see
[Migrate from ECS](../aws/deploy-amazon-eks.mdx#migrate-from-ecs).

:::

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
the development branch every day. See [Follow bleeding-edge](#follow-bleeding-edge).

:::

## Prerequisites

* An AWS account and an IAM principal that can create VPC, EKS, and IAM resources. With an
  [existing cluster](#existing-vpc-or-eks-cluster), it needs IAM and administrator access to the
  cluster instead of VPC and EKS rights
* Terraform 1.6+ (or OpenTofu), Helm 3.8+, `kubectl`, and the AWS CLI
* A Git repository for the configuration, with a read-only deploy key for ArgoCD
* An S3 bucket for the Terraform state
* An issued [ACM certificate](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)
  for each environment's hostname, or a wildcard certificate

## Repository layout

```text
terraform/                    # bootstrap, one state per environment
  main.tf  variables.tf  outputs.tf
  argocd-values.yaml          # ArgoCD settings, including the health check for the environment
  env/main.tfvars             # a new VPC and cluster
  env/existing-vpc.tfvars.example
  env/existing-cluster.tfvars.example
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

1. Terraform creates the cluster, or reads the one you name, then installs ArgoCD and a root Application that points at
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
[IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
(IRSA), and RDS has
[IAM database authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
enabled for the Datagrok admin role. Generated passwords are kept in AWS Secrets Manager.

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
                vpcId             = local.vpc_id
                dbSubnetGroup     = local.db_subnet_group
                oidcProvider      = local.oidc_provider
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

The `local.*` facts come from the VPC and cluster Terraform creates, or from the ones you name. See
[Existing VPC or EKS cluster](#existing-vpc-or-eks-cluster).

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
   `terraform/env/<env>.tfvars`. To use your own VPC or cluster, start from one of the
   `.tfvars.example` files instead. See [Existing VPC or EKS cluster](#existing-vpc-or-eks-cluster).
1. Create the cluster, or connect to yours, and install ArgoCD:

   ```bash
   cd terraform
   terraform init -backend-config="bucket=<state-bucket>" -backend-config="key=datagrok/main.tfstate" \
     -backend-config="region=us-east-1"
   terraform apply -var-file=env/main.tfvars
   ```

1. Give ArgoCD read access to the config repo:

   ```bash
   $(terraform output -raw kubeconfig_command)
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

## Existing VPC or EKS cluster

By default Terraform creates a VPC with public, private, and database subnets in three availability
zones, and an EKS cluster in it. It can use a VPC or a cluster you already run instead. Everything
after Terraform, including RDS, S3, the IAM role of Datagrok, and the Datagrok chart, works the same.

| Variable | Description |
|----------|-------------|
| `existing_vpc_id` | Create the cluster in this VPC |
| `existing_private_subnet_ids` | With `existing_vpc_id`: subnets for the cluster nodes |
| `existing_cluster_name` | Install into this EKS cluster. Its VPC is used too |
| `existing_node_security_group_id` | With `existing_cluster_name`: the security group of the nodes, allowed to reach RDS. Default: the cluster security group |
| `db_subnet_ids` | With either option: subnets for RDS. Terraform creates the `datagrok-<env>` DB subnet group from them |
| `install_lb_controller` | `false` if the cluster already runs the AWS Load Balancer Controller |

With either option, `vpc_cidr` is ignored. With an existing cluster, so are `kubernetes_version` and
the node group variables. `terraform destroy` removes only what Terraform created, never your VPC
or cluster.

### Existing VPC

```hcl title="terraform/env/main.tfvars"
env                         = "main"
existing_vpc_id             = "vpc-0123"
existing_private_subnet_ids = ["subnet-0aaa", "subnet-0bbb", "subnet-0ccc"]
db_subnet_ids               = ["subnet-0ddd", "subnet-0eee"]
config_repo_url             = "git@github.com:acme/datagrok-config.git"
```

The VPC needs:

* Private subnets for the nodes, in at least two availability zones, with a route to a NAT gateway.
  The nodes pull images from Docker Hub.
* Private subnets for RDS in at least two availability zones. They can be the node subnets.
* For an internet-facing load balancer, public subnets tagged `kubernetes.io/role/elb: 1`, so the
  [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/)
  finds them. Or name the subnets in the environment file:

  ```yaml title="gitops/envs/main.yaml (excerpt)"
  appValues:
    ingress:
      annotations:
        alb.ingress.kubernetes.io/subnets: subnet-0fff,subnet-0ggg
  ```

### Existing cluster

```hcl title="terraform/env/main.tfvars"
env                   = "main"
existing_cluster_name = "my-cluster"
db_subnet_ids         = ["subnet-0aaa", "subnet-0bbb"]
install_lb_controller = false   # if the cluster already runs one
config_repo_url       = "git@github.com:acme/datagrok-config.git"
```

Terraform reads the cluster, its VPC, and its IAM OIDC provider, creates the IAM roles of the
controllers, and installs ArgoCD. The cluster needs:

* An [IAM OIDC provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html),
  which IRSA requires. Terraform reads it and stops if it doesn't exist. To create it:
  `eksctl utils associate-iam-oidc-provider --cluster my-cluster --approve`.
* Administrator access for the principal that runs Terraform, for example an
  [access entry](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) with
  `AmazonEKSClusterAdminPolicy`, and an API endpoint reachable from where Terraform runs.
* Free capacity for Datagrok, about 4 vCPU and 8 GiB, and for ArgoCD, Crossplane with its six AWS
  providers, and External Secrets.
* Nodes in the security group that RDS allows. Managed node groups use the cluster security group,
  which is the default. For other nodes, set `existing_node_security_group_id`.
* No ArgoCD, Crossplane, or External Secrets of its own. The templates install all three, ArgoCD in
  the `argocd` namespace.
* If it runs the AWS Load Balancer Controller, a controller that handles the `alb` ingress class,
  which is its default.

The VPC requirements above apply to the cluster's VPC too.

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
| `allowDataDeletion` | `false` | `true` lets removal delete the database, bucket and log group. See [Safeguards](#safeguards) |
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
`terraform apply`. To use your own VPC or cluster, see
[Existing VPC or EKS cluster](#existing-vpc-or-eks-cluster).

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
| Follow the development builds | See [Follow bleeding-edge](#follow-bleeding-edge) |
| Change RDS or S3 settings | Pull request to the environment file |
| Preview a change | `terraform plan` for the cluster. `argocd app diff` and `crossplane render` for Applications and AWS resources |

### Follow bleeding-edge

`bleeding-edge` is the current state of Datagrok development. Datagrok builds it from the `master`
branch every night, sometimes also during the day, and publishes everything under moving tags: the `bleeding-edge` service images, the Datagrok chart `0.0.3-bleeding-edge-helm`, and the
`datagrok-env` and `crossplane-aws` packages `0.0.3-bleeding-edge` (see
[Tag conventions](../images.md#tag-conventions)). It isn't a tested release. Use it for a development
or evaluation environment that tries new features before they ship, not for production: database
migrations only run forward, so an environment that ran `bleeding-edge` can't go back to an older
release.

Set the version in the environment file:

```yaml title="gitops/envs/dev.yaml (excerpt)"
datagrok:
  version: 0.0.3-bleeding-edge
```

A moving tag doesn't redeploy anything by itself. Crossplane checks the `crossplane-aws` package for a
new build, but ArgoCD treats a chart version as fixed and can serve a cached copy for up to a day, and
running pods keep the image they started with. To get each night's build, refresh the environment
daily with a scheduled job that resolves the moving image tags to digests and commits them under
`images`. Every refresh is then a commit that ArgoCD rolls out, and that you can revert. For example,
with GitHub Actions in the config repo:

```yaml title=".github/workflows/refresh-bleeding-edge.yaml"
name: Refresh bleeding-edge
on:
  schedule:
    - cron: "0 7 * * *"   # after the nightly build
  workflow_dispatch:
permissions:
  contents: write
jobs:
  refresh:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Pin the latest bleeding-edge images
        run: |
          file=gitops/envs/dev.yaml
          for pair in datagrok:datagrok grokPipe:grok_pipe spawner:grok_spawner grokConnectAdbc:grok_connect_adbc; do
            digest=$(docker buildx imagetools inspect "datagrok/${pair#*:}:bleeding-edge" --format '{{.Manifest.Digest}}')
            yq -i ".images.${pair%%:*} = \"$digest\"" "$file"
          done
          git diff --quiet && exit 0
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git commit -am "Refresh bleeding-edge images" && git push
```

The job pins the services whose chart default is `bleeding-edge`. Services that the chart pins to a
version, such as `grokConnect`, follow the chart. After a refresh that changes the chart or the
composition, run `argocd app get datagrok-<env> --hard-refresh` to pick up the new build right away.

## Safeguards

Crossplane has no plan step that asks AWS what a change will do. A preview shows which fields change,
not whether AWS modifies, restarts, or replaces a resource. The templates protect data against that:

* Removing the environment never deletes its data. The RDS instance, the S3 bucket and the log group
  are created with `deletionPolicy: Orphan`, so deleting the `DatagrokEnvironment`, the
  `datagrok-<env>` application, the crossplane-aws package or its XRD leaves them in AWS. Restoring
  the environment with the same `env` adopts them again.
* `allowDataDeletion` is the safety switch. Until it is `true` on the running environment, Kubernetes
  rejects any change that turns off `db.deletionProtection`, turns on `db.skipFinalSnapshot` or
  `storage.forceDestroy`, or lowers `db.backupRetentionDays` or `storage.noncurrentVersionDays`. Set
  it in its own commit and sync it before you lower a guard: a commit that does both is rejected. The
  `env` of an environment can't be changed.
* Behind the switch, RDS has deletion protection and takes a final snapshot, automated backups are
  kept for their retention period after the instance is deleted, and a non-empty bucket can't be
  deleted.
* Generated passwords are created once and kept in Secrets Manager under `datagrok/<env>`. Neither
  ArgoCD nor a resync regenerates them.
* Every version is pinned: the Datagrok release by `datagrok.version`, and the providers,
  functions, and controllers in `gitops/platform` and `gitops/bootstrap`. If you run a second
  environment, upgrade it first.

## Add an environment

Each environment gets its own cluster, ArgoCD, and AWS resources, built from the same templates:

1. Copy `terraform/env/main.tfvars` to `terraform/env/<env>.tfvars`. Set `env` and a VPC CIDR that
   doesn't overlap with other environments, or [another existing VPC or cluster](#existing-vpc-or-eks-cluster).
   A cluster holds one environment, because each environment installs its own ArgoCD.
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
| Datagrok can't connect to the database | `db.host` in the environment file must match the RDS endpoint, and the `datagrok-db-bootstrap` job must have completed. In an existing cluster, the nodes must be in the security group RDS allows: set `existing_node_security_group_id` |
| `terraform apply` can't find an OIDC provider | The existing cluster has no IAM OIDC provider. Create it with `eksctl utils associate-iam-oidc-provider` |
| `terraform apply` is denied by Kubernetes | The principal running Terraform has no administrator access to the existing cluster. Add an access entry |
| The ingress gets no load balancer | The AWS Load Balancer Controller finds no public subnets. Tag them `kubernetes.io/role/elb: 1`, or set `alb.ingress.kubernetes.io/subnets` |

## See also

* [Install Datagrok with Helm](install-helm-chart.md): the chart this page deploys, and all its values
* [AWS CloudFormation (EKS)](../aws/deploy-amazon-eks.mdx): EKS, RDS, and S3 as one CloudFormation stack, also on an existing cluster
* [AWS CloudFormation (ECS)](../aws/deploy-amazon-ecs.mdx): for existing ECS stacks
* [Images and versions](../images.md): image tags, chart tags, and the default version of each service
* [Upgrade](../upgrade.md)
