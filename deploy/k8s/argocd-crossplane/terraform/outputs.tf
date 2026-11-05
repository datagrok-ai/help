output "cluster_name" {
  value = local.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.region}"
}

output "crossplane_role_arn" {
  value = aws_iam_role.crossplane.arn
}
