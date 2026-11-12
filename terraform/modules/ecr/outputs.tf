output "repository_urls" {
  description = "Map of service_name => ECR repository URL ({account}.dkr.ecr.{region}.amazonaws.com/petclinic-{env}/{service})."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service_name => ECR repository ARN (for CI push / node pull IAM policies)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_names" {
  description = "Map of service_name => ECR repository name (petclinic-{env}/{service})."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.name }
}

output "registry_id" {
  description = "AWS account ID that owns the registry."
  value       = one(distinct([for repo in aws_ecr_repository.this : repo.registry_id]))
}

output "registry_url" {
  description = "Registry hostname for docker login ({account}.dkr.ecr.{region}.amazonaws.com)."
  value       = one(distinct([for repo in aws_ecr_repository.this : split("/", repo.repository_url)[0]]))
}

output "environment" {
  description = "Environment the repositories belong to."
  value       = var.environment
}

output "image_tag_mutability" {
  description = "Tag mutability applied to every repository."
  value       = var.image_tag_mutability
}
