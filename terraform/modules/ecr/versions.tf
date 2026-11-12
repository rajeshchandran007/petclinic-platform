terraform {
  required_version = ">= 1.10.0" # cross-variable validation (kms_key_arn) needs >= 1.9

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
