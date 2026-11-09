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
