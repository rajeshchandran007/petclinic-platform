# Module: secrets
# Secrets Manager secrets for application credentials (E-7)
#
# Placeholder created by PETPLAT-1. Resources are implemented in the owning epic.
# See docs/technical-spec.md#module-secrets for the input/output contract.

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
