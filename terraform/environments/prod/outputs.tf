output "aws_region" {
  description = "AWS region this environment is deployed to."
  value       = var.aws_region
}

output "environment" {
  description = "Environment name."
  value       = var.environment
}

output "name_prefix" {
  description = "Resource name prefix (petclinic-{env})."
  value       = local.name_prefix
}

output "common_tags" {
  description = "Tags applied to every resource via provider default_tags."
  value       = local.common_tags
}

################################################################################
# Networking
################################################################################

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID."
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS node security group ID."
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = module.vpc.alb_sg_id
}

################################################################################
# EKS
################################################################################

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "eks_node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "eks_node_role_arn" {
  description = "Node IAM role ARN."
  value       = module.eks.node_role_arn
}

output "eks_ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI driver."
  value       = module.eks.ebs_csi_role_arn
}

output "eks_cluster_admin_principal_arns" {
  description = "IAM principals with cluster-admin access entries."
  value       = module.eks.cluster_admin_principal_arns
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl for the cluster."
  value       = module.eks.kubeconfig_command
}
