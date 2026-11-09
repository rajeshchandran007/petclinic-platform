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

################################################################################
# Networking (E-2: PETPLAT-9/10) - VPC, public subnets, IGW, baseline SGs
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
  cluster_name        = "${var.project}-${var.environment}" # must match EKS cluster name (E-3)

  flow_logs_traffic_type = "ALL"

  tags = merge(var.additional_tags, { Component = "networking" })
}

################################################################################
# EKS cluster (E-3: PETPLAT-12/13/14/84, wired by PETPLAT-17)
################################################################################

module "eks" {
  source = "../../modules/eks"

  project         = var.project
  environment     = var.environment
  cluster_version = var.eks_cluster_version

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  cluster_endpoint_public_access_cidrs = var.eks_public_access_cidrs
  cluster_admin_principal_arns         = var.eks_cluster_admin_principal_arns

  # technical-spec.md#managed-node-group
  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
  node_disk_size      = 20

  tags = merge(var.additional_tags, { Component = "compute" })
}

# Remaining module calls are added by their owning epics:
#   module "ecr"           -> E-4  (terraform/modules/ecr)
#   module "rds"           -> E-5  (terraform/modules/rds)
#   module "dns"           -> E-6  (terraform/modules/dns)
#   module "secrets"       -> E-7  (terraform/modules/secrets)
#   module "observability" -> E-11 (terraform/modules/observability)
#   module "karpenter"     -> E-14 (terraform/modules/karpenter)
