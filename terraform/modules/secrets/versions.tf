terraform {
  # >= 1.11 for write-only arguments (secret_string_wo); ephemeral input
  # variables (>= 1.10) keep secret values out of state and plan files.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}
