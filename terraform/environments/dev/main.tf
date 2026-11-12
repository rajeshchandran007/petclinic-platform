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

  flow_logs_traffic_type = "REJECT"

  tags = merge(var.additional_tags, { Component = "networking" })
}

################################################################################
# EKS cluster (E-3: PETPLAT-12/13/14/84, wired by PETPLAT-15)
################################################################################

module "eks" {
  source = "../../modules/eks"

  project         = var.project
  environment     = var.environment
  cluster_version = var.eks_cluster_version

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  # LB controller may never modify these perimeter SGs (PETPLAT-29 guardrail).
  lb_controller_protected_security_group_ids = [module.vpc.rds_sg_id, module.vpc.alb_sg_id]

  cluster_endpoint_public_access_cidrs = var.eks_public_access_cidrs
  cluster_admin_principal_arns         = var.eks_cluster_admin_principal_arns
  # Dev only: lets the account root user view cluster resources in the EKS console.
  grant_root_cluster_admin = true

  # technical-spec.md#managed-node-group
  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
  node_disk_size      = 20

  tags = merge(var.additional_tags, { Component = "compute" })
}

################################################################################
# Container registry (E-4: PETPLAT-18/19, wired by PETPLAT-20)
################################################################################

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  # technical-spec.md#repositories-8-per-environment
  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]

  # Dev: MUTABLE so the same tag can be re-pushed during development.
  image_tag_mutability = "MUTABLE"

  # Lifecycle: keep last 10 tagged images, expire untagged after 7 days
  max_tagged_image_count     = 10
  untagged_image_expiry_days = 7

  tags = merge(var.additional_tags, { Component = "registry" })
}

################################################################################
# Database (E-5: PETPLAT-22/23, wired by PETPLAT-25)
################################################################################

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  # technical-spec.md#instance-configuration
  engine_version    = var.rds_engine_version
  instance_class    = "db.t4g.micro"
  multi_az          = false
  allocated_storage = 20
  storage_type      = "gp2"

  # Dev: disposable — no final snapshot, secret deletable immediately for re-create.
  backup_retention_period        = 7
  skip_final_snapshot            = true
  deletion_protection            = false
  secret_recovery_window_in_days = 0
  apply_immediately              = true

  tags = merge(var.additional_tags, { Component = "database" })
}

################################################################################
# DNS & TLS (E-6: PETPLAT-28/31, wired by PETPLAT-32)
################################################################################

module "dns" {
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment

  # technical-spec.md#route-53 — dev creates the zone; prod reuses it.
  domain_name        = var.domain_name
  create_hosted_zone = true

  # Wildcard cert (*.{domain}) covers petclinic-dev.{domain}. Validation waits
  # until the zone's NS records are delegated at the registrar.
  wait_for_certificate_validation = var.wait_for_certificate_validation

  # petclinic-dev.{domain} -> ALB. The ALB name is pinned by the Ingress
  # (alb.ingress.kubernetes.io/load-balancer-name). Enable after the Ingress
  # has created the ALB (PETPLAT-31).
  record_name = "${var.project}-${var.environment}"
  alb_name    = var.create_alb_dns_record ? "${local.name_prefix}-alb" : null

  tags = merge(var.additional_tags, { Component = "dns" })
}

# Remaining module calls are added by their owning epics:
#   module "secrets"       -> E-7  (terraform/modules/secrets)
#   module "observability" -> E-11 (terraform/modules/observability)
#   module "karpenter"     -> E-14 (terraform/modules/karpenter)
