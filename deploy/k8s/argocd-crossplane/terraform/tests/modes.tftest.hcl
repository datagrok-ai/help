# Plans every network/cluster mode against mocked providers, no AWS account needed:
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      endpoint              = "https://existing.eks.example.com"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXISTING" }] }]
      vpc_config            = [{ vpc_id = "vpc-cluster", cluster_security_group_id = "sg-cluster" }]
    }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-cluster", cidr_block = "172.31.0.0/16" }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXISTING" }
  }
  mock_resource "aws_db_subnet_group" {
    defaults = { name = "datagrok-main" }
  }
}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}
mock_provider "null" {}

variables {
  env             = "main"
  config_repo_url = "git@github.com:acme/cfg.git"
}

run "new_vpc_and_cluster" {
  command = plan
  assert {
    condition     = length(module.vpc) == 1 && length(module.eks) == 1 && length(aws_db_subnet_group.existing_vpc) == 0
    error_message = "default mode must create the VPC and the cluster"
  }
  assert {
    condition     = local.vpc_cidr == "10.0.0.0/16" && local.cluster_name == "datagrok-main"
    error_message = "new VPC facts"
  }
}

run "existing_vpc" {
  command = plan
  variables {
    existing_vpc_id             = "vpc-mine"
    existing_private_subnet_ids = ["subnet-a", "subnet-b"]
    db_subnet_ids               = ["subnet-c", "subnet-d"]
  }
  assert {
    condition     = length(module.vpc) == 0 && length(module.eks) == 1 && length(aws_db_subnet_group.existing_vpc) == 1
    error_message = "existing VPC: no VPC module, a new cluster, a DB subnet group"
  }
  assert {
    condition     = local.db_subnet_group == "datagrok-main" && local.cluster_name == "datagrok-main"
    error_message = "existing VPC facts"
  }
}

run "existing_cluster" {
  command = plan
  variables {
    existing_cluster_name = "my-cluster"
    db_subnet_ids         = ["subnet-c", "subnet-d"]
    install_lb_controller = false
  }
  assert {
    condition     = length(module.vpc) == 0 && length(module.eks) == 0 && length(module.lb_controller_irsa) == 0
    error_message = "existing cluster: nothing created for network, cluster, or LB controller"
  }
  assert {
    condition = (local.cluster_name == "my-cluster" && local.vpc_id == "vpc-cluster"
      && local.oidc_provider == "oidc.eks.us-east-1.amazonaws.com/id/EXISTING"
    && local.node_security_group_id == "sg-cluster" && local.vpc_cidr == "172.31.0.0/16")
    error_message = "existing cluster facts"
  }
}

run "existing_cluster_own_node_sg" {
  command = plan
  variables {
    existing_cluster_name           = "my-cluster"
    db_subnet_ids                   = ["subnet-c", "subnet-d"]
    existing_node_security_group_id = "sg-nodes"
  }
  assert {
    condition     = local.node_security_group_id == "sg-nodes"
    error_message = "explicit node security group"
  }
}

run "existing_cluster_without_db_subnets_fails" {
  command = plan
  variables {
    existing_cluster_name = "my-cluster"
  }
  expect_failures = [terraform_data.inputs]
}

run "existing_vpc_without_node_subnets_fails" {
  command = plan
  variables {
    existing_vpc_id = "vpc-mine"
    db_subnet_ids   = ["subnet-c", "subnet-d"]
  }
  expect_failures = [terraform_data.inputs]
}

run "monitoring_off_by_default" {
  command = plan
  assert {
    condition     = length(module.cloudwatch_exporter_irsa) == 0 && length(aws_eks_addon.ebs_csi) == 0
    error_message = "monitoring is off by default: no exporter role, no EBS driver"
  }
}

run "monitoring_local" {
  command = plan
  variables {
    monitoring_mode = "local"
  }
  assert {
    condition     = length(module.cloudwatch_exporter_irsa) == 1 && length(aws_eks_addon.ebs_csi) == 1
    error_message = "local monitoring: exporter role and EBS driver"
  }
}

run "monitoring_external_on_existing_cluster" {
  command = plan
  variables {
    existing_cluster_name = "my-cluster"
    db_subnet_ids         = ["subnet-c", "subnet-d"]
    monitoring_mode       = "external"
  }
  assert {
    condition     = length(module.cloudwatch_exporter_irsa) == 1 && length(aws_eks_addon.ebs_csi) == 0
    error_message = "external monitoring: exporter role only, the external Prometheus stores the data"
  }
}

run "monitoring_unknown_mode_fails" {
  command = plan
  variables {
    monitoring_mode = "on"
  }
  expect_failures = [var.monitoring_mode]
}
