variable "env" {
  description = "Environment name: dev, test or prod. Feeds every resource name (datagrok-<env>)."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
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
