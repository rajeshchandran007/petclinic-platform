terraform {
  # >= 1.11 for write-only arguments (password_wo, secret_string_wo) and
  # ephemeral resources, which keep the master password out of state.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
