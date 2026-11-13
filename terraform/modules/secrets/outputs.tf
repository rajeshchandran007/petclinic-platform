################################################################################
# Secrets (PETPLAT-33)
################################################################################

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (petclinic/{env}/openai-api-key)."
  value       = aws_secretsmanager_secret.openai_api_key.arn
}

output "openai_secret_name" {
  description = "Secrets Manager name of the OpenAI API key secret."
  value       = aws_secretsmanager_secret.openai_api_key.name
}

output "config_server_git_username_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git username (null when not created)."
  value       = try(aws_secretsmanager_secret.config_server_git_username[0].arn, null)
}

output "config_server_git_password_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git password (null when not created)."
  value       = try(aws_secretsmanager_secret.config_server_git_password[0].arn, null)
}

output "secret_arns" {
  description = "Map of logical name => Secrets Manager ARN for every secret this module manages."
  value = merge(
    { openai-api-key = aws_secretsmanager_secret.openai_api_key.arn },
    var.create_config_server_git_secrets ? {
      config-server-git-username = aws_secretsmanager_secret.config_server_git_username[0].arn
      config-server-git-password = aws_secretsmanager_secret.config_server_git_password[0].arn
    } : {},
  )
}

################################################################################
# ESO IRSA role (PETPLAT-37)
################################################################################

output "eso_role_arn" {
  description = "IRSA role ARN for the ESO service account (eks.amazonaws.com/role-arn annotation on external-secrets/external-secrets-sa)."
  value       = aws_iam_role.eso.arn
}

output "eso_role_name" {
  description = "IRSA role name for External Secrets Operator."
  value       = aws_iam_role.eso.name
}

output "eso_secret_arn_pattern" {
  description = "Secrets Manager ARN pattern the ESO role may read (petclinic/{env}/*)."
  value       = local.eso_secret_arn_pattern
}
