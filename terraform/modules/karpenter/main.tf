# Module: karpenter
# Karpenter IAM roles, SQS interruption queue, EventBridge rules (E-14)
#
# Placeholder created by PETPLAT-1. Resources are implemented in the owning epic.
# See docs/technical-spec.md#module-karpenter for the input/output contract.

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
