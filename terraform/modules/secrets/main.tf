# Module: secrets
# Non-RDS application secrets in AWS Secrets Manager (E-7: PETPLAT-33) and the
# IRSA role External Secrets Operator uses to read them (PETPLAT-37, irsa.tf).
#
# Spec: docs/technical-spec.md#secrets-management, #module-secrets
#
# RDS credentials (petclinic/{env}/rds-credentials) are owned by the rds module
# (PETPLAT-23) and are deliberately NOT created here.
#
# Secret values never touch Terraform state or plan files: they come in through
# *ephemeral* sensitive variables and are written only to the write-only argument
# `secret_string_wo`. Terraform re-sends a value only when its *_version input
# changes, so to rotate a value: export the new value and bump the version.
#
# All secrets use the AWS-managed aws/secretsmanager KMS key
# (technical-spec.md#encryption-matrix).

locals {
  name_prefix   = "${var.project}-${var.environment}"
  secret_prefix = "${var.project}/${var.environment}"

  openai_secret_name       = "${local.secret_prefix}/openai-api-key"
  config_git_username_name = "${local.secret_prefix}/config-server/git-username"
  config_git_password_name = "${local.secret_prefix}/config-server/git-password"

  # Non-secret sentinel stored when a value is not supplied, so the secret, its
  # ExternalSecret and the K8s Secret still exist (genai-service is optional).
  # Variable validation only allows it for *_version == 1, so a version bump can
  # never overwrite a real value with the sentinel.
  placeholder_value = "PLACEHOLDER-NOT-CONFIGURED"

  # Required tags last so callers cannot override them (same as the rds module).
  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# OpenAI API key — petclinic/{env}/openai-api-key (plaintext)
# Consumed by genai-service via ExternalSecret k8s/base/external-secrets/openai-api-key.yaml
################################################################################

resource "aws_secretsmanager_secret" "openai_api_key" {
  #checkov:skip=CKV2_AWS_57:Third-party API key; rotated manually by bumping openai_api_key_version
  #checkov:skip=CKV_AWS_149:Encrypted with the AWS-managed aws/secretsmanager key per technical-spec.md#secrets
  name                    = local.openai_secret_name
  description             = "OpenAI API key for ${local.name_prefix} genai-service (plaintext)"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.tags, { Name = local.openai_secret_name })
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id = aws_secretsmanager_secret.openai_api_key.id

  # genai-service is optional (technical-spec.md#genai-service-configuration). When
  # no key is supplied a non-secret placeholder is stored so the secret, the
  # ExternalSecret and the K8s Secret still exist; set TF_VAR_openai_api_key and
  # bump openai_api_key_version to write the real key.
  secret_string_wo         = coalesce(var.openai_api_key, local.placeholder_value)
  secret_string_wo_version = var.openai_api_key_version
}

################################################################################
# Optional: Config Server Git credentials (only for a private config repo)
#   petclinic/{env}/config-server/git-username
#   petclinic/{env}/config-server/git-password
################################################################################

resource "aws_secretsmanager_secret" "config_server_git_username" {
  #checkov:skip=CKV2_AWS_57:Git credential; rotated manually by bumping config_server_git_credentials_version
  #checkov:skip=CKV_AWS_149:Encrypted with the AWS-managed aws/secretsmanager key per technical-spec.md#secrets
  count = var.create_config_server_git_secrets ? 1 : 0

  name                    = local.config_git_username_name
  description             = "Config Server Git username for ${local.name_prefix} (plaintext)"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.tags, { Name = local.config_git_username_name })
}

resource "aws_secretsmanager_secret_version" "config_server_git_username" {
  count = var.create_config_server_git_secrets ? 1 : 0

  secret_id                = aws_secretsmanager_secret.config_server_git_username[0].id
  secret_string_wo         = coalesce(var.config_server_git_username, local.placeholder_value)
  secret_string_wo_version = var.config_server_git_credentials_version
}

resource "aws_secretsmanager_secret" "config_server_git_password" {
  #checkov:skip=CKV2_AWS_57:Git credential; rotated manually by bumping config_server_git_credentials_version
  #checkov:skip=CKV_AWS_149:Encrypted with the AWS-managed aws/secretsmanager key per technical-spec.md#secrets
  count = var.create_config_server_git_secrets ? 1 : 0

  name                    = local.config_git_password_name
  description             = "Config Server Git password / access token for ${local.name_prefix} (plaintext)"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.tags, { Name = local.config_git_password_name })
}

resource "aws_secretsmanager_secret_version" "config_server_git_password" {
  count = var.create_config_server_git_secrets ? 1 : 0

  secret_id                = aws_secretsmanager_secret.config_server_git_password[0].id
  secret_string_wo         = coalesce(var.config_server_git_password, local.placeholder_value)
  secret_string_wo_version = var.config_server_git_credentials_version
}
