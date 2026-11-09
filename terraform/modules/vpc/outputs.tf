output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ). Used by EKS, RDS subnet group and ALB."
  value       = aws_subnet.public[*].id
}

output "subnet_ids" {
  description = "All subnet IDs in the VPC (alias of public_subnet_ids; the design is all-public)."
  value       = aws_subnet.public[*].id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "eks_cluster_sg_id" {
  description = "EKS cluster (control plane) security group ID."
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS MySQL security group ID."
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "security_group_ids" {
  description = "Map of all baseline security group IDs."
  value = {
    eks_cluster = aws_security_group.eks_cluster.id
    eks_node    = aws_security_group.eks_node.id
    rds         = aws_security_group.rds.id
    alb         = aws_security_group.alb.id
  }
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC Flow Logs (null when disabled)."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
