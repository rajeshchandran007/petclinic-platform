locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    var.additional_tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

# Module calls are added by their owning epics:
#   module "vpc"           -> E-2  (terraform/modules/vpc)
#   module "eks"           -> E-3  (terraform/modules/eks)
#   module "ecr"           -> E-4  (terraform/modules/ecr)
#   module "rds"           -> E-5  (terraform/modules/rds)
#   module "dns"           -> E-6  (terraform/modules/dns)
#   module "secrets"       -> E-7  (terraform/modules/secrets)
#   module "observability" -> E-11 (terraform/modules/observability)
#   module "karpenter"     -> E-14 (terraform/modules/karpenter)
