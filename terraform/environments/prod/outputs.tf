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

################################################################################
# ECR
################################################################################

output "ecr_repository_urls" {
  description = "Map of service name => ECR repository URL."
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name => ECR repository ARN."
  value       = module.ecr.repository_arns
}

output "ecr_registry_url" {
  description = "ECR registry hostname for docker login."
  value       = module.ecr.registry_url
}

################################################################################
# RDS
################################################################################

output "rds_endpoint" {
  description = "RDS MySQL endpoint hostname."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS MySQL port."
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "RDS instance identifier."
  value       = module.rds.db_instance_id
}

output "rds_jdbc_url" {
  description = "JDBC URL for SPRING_DATASOURCE_URL."
  value       = module.rds.jdbc_url
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN of petclinic/{env}/rds-credentials (for External Secrets Operator)."
  value       = module.rds.secret_arn
}

output "rds_secret_name" {
  description = "Secrets Manager name of the RDS credentials secret."
  value       = module.rds.secret_name
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for kube-system/aws-load-balancer-controller."
  value       = module.eks.lb_controller_role_arn
}
