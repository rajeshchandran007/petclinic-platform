variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "tags" {
  description = "Additional tags merged into the required Project/Environment/ManagedBy tags."
  type        = map(string)
  default     = {}
}

variable "secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps a deleted secret recoverable (0 = delete immediately, 7-30 otherwise)."
  type        = number
  default     = 7

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

################################################################################
# OpenAI API key (PETPLAT-33)
################################################################################

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Supply via TF_VAR_openai_api_key, never in a file. Ephemeral + write-only: never stored in state or plan files. Only written when openai_api_key_version changes; null (allowed only at version 1) stores a non-secret placeholder."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  # A version bump re-writes the secret. Without the key that would replace a
  # live key with the placeholder, so require the key for any version > 1.
  validation {
    condition     = var.openai_api_key != null || var.openai_api_key_version == 1
    error_message = "openai_api_key_version > 1 re-writes the secret: export TF_VAR_openai_api_key with the key in the same shell."
  }
}

variable "openai_api_key_version" {
  description = "Increment to (re)write openai_api_key to Secrets Manager (write-only update trigger)."
  type        = number
  default     = 1
}

################################################################################
# Config Server Git credentials (optional, PETPLAT-33)
################################################################################

variable "create_config_server_git_secrets" {
  description = "Create petclinic/{env}/config-server/git-username and git-password (only needed for a private config repo)."
  type        = bool
  default     = false
}

variable "config_server_git_username" {
  description = "Config Server Git username. Supply via TF_VAR_config_server_git_username. Ephemeral + write-only."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "config_server_git_password" {
  description = "Config Server Git password or access token. Supply via TF_VAR_config_server_git_password. Ephemeral + write-only."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = (var.config_server_git_username == null) == (var.config_server_git_password == null)
    error_message = "Set both config_server_git_username and config_server_git_password, or neither."
  }

  validation {
    condition     = var.config_server_git_password != null || var.config_server_git_credentials_version == 1
    error_message = "config_server_git_credentials_version > 1 re-writes the Git credentials: export TF_VAR_config_server_git_username and TF_VAR_config_server_git_password."
  }
}

variable "config_server_git_credentials_version" {
  description = "Increment to (re)write the Config Server Git credentials to Secrets Manager."
  type        = number
  default     = 1
}

################################################################################
# ESO IRSA role (PETPLAT-37)
################################################################################

variable "oidc_provider_arn" {
  description = "EKS cluster IAM OIDC provider ARN (eks module output oidc_provider_arn), the IRSA trust principal."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/.+", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}

variable "eso_namespace" {
  description = "Namespace of the External Secrets Operator service account."
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account" {
  description = "External Secrets Operator service account name (referenced by the ClusterSecretStore)."
  type        = string
  default     = "external-secrets-sa"
}

variable "kms_key_arns" {
  description = "Customer-managed KMS key ARNs that encrypt petclinic secrets. Empty (default) when secrets use the AWS-managed aws/secretsmanager key."
  type        = list(string)
  default     = []
}
