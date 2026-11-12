################################################################################
# Cluster (PETPLAT-12)
################################################################################

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_managed_security_group_id" {
  description = "Security group EKS creates and attaches to the control plane (in addition to cluster_sg_id)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (IRSA trust-policy principal)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL of the cluster."
  value       = aws_iam_openid_connect_provider.this.url
}

################################################################################
# Node group (PETPLAT-13)
################################################################################

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "Node IAM role ARN."
  value       = aws_iam_role.node.arn
}

################################################################################
# Access (PETPLAT-14)
################################################################################

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig context for this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name}"
}

output "cluster_admin_principal_arns" {
  description = "IAM principals with cluster-admin access entries."
  value       = sort(tolist(local.cluster_admin_principal_arns))
}

################################################################################
# Add-ons (PETPLAT-84)
################################################################################

output "addon_versions" {
  description = "Installed EKS add-on versions."
  value = merge(
    { for k, a in aws_eks_addon.before_compute : k => a.addon_version },
    { for k, a in aws_eks_addon.after_compute : k => a.addon_version },
  )
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN used by the EBS CSI driver controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller service account (null when disabled)."
  value       = try(aws_iam_role.lb_controller[0].arn, null)
}

output "lb_controller_policy_arn" {
  description = "IAM policy ARN attached to the AWS Load Balancer Controller role (null when disabled)."
  value       = try(aws_iam_policy.lb_controller[0].arn, null)
}
