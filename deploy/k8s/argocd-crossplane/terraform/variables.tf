variable "env" {
  description = "Short environment name, e.g. main. Feeds every resource name (datagrok-<env>)."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  description = "Address range of the VPC Terraform creates. Ignored with an existing VPC or cluster."
  type        = string
  default     = "10.0.0.0/16"
}

variable "existing_cluster_name" {
  description = "Install into this EKS cluster instead of creating one. Its VPC is used too."
  type        = string
  default     = ""
}

variable "existing_node_security_group_id" {
  description = "With existing_cluster_name: security group of the nodes, allowed to reach RDS. Default: the cluster security group."
  type        = string
  default     = ""
}

variable "existing_vpc_id" {
  description = "Create the cluster in this VPC instead of a new one. Needs existing_private_subnet_ids."
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "With existing_vpc_id: private subnets for the cluster nodes, with outbound internet access."
  type        = list(string)
  default     = []
}

variable "db_subnet_ids" {
  description = "With an existing VPC or cluster: private subnets for RDS, in at least two availability zones."
  type        = list(string)
  default     = []
}

variable "install_lb_controller" {
  description = "Install the AWS Load Balancer Controller. Set to false if the cluster already runs one."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m6i.xlarge"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "argocd_chart_version" {
  type    = string
  default = "7.6.12"
}

variable "config_repo_url" {
  description = "Git repo ArgoCD syncs from, e.g. git@github.com:acme/datagrok-config.git"
  type        = string
}

variable "config_repo_revision" {
  type    = string
  default = "main"
}
