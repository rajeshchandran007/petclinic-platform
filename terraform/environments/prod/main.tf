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

  # LB controller may never modify these perimeter SGs (PETPLAT-29 guardrail).
  lb_controller_protected_security_group_ids = [module.vpc.rds_sg_id, module.vpc.alb_sg_id]

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

  # Prod: IMMUTABLE so a deployed tag can never be overwritten.
  image_tag_mutability = "IMMUTABLE"

  # Lifecycle: keep last 10 tagged images, expire untagged after 7 days
  max_tagged_image_count     = 10
  untagged_image_expiry_days = 7

  tags = merge(var.additional_tags, { Component = "registry" })
}

################################################################################
# Database (E-5: PETPLAT-22/23, wired by PETPLAT-27)
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

  # Prod: keep a final snapshot and 30 days of backups. Single-AZ db.t4g.micro is a
  # learning-project cost optimisation — real production would use Multi-AZ.
  backup_retention_period        = 30
  skip_final_snapshot            = false
  delete_automated_backups       = false
  deletion_protection            = false
  secret_recovery_window_in_days = 7
  apply_immediately              = false

  tags = merge(var.additional_tags, { Component = "database" })
}

################################################################################
# Secrets (E-7: PETPLAT-33/37) - non-RDS app secrets + ESO IRSA role
################################################################################

module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  # technical-spec.md#secrets — petclinic/prod/openai-api-key. Values are
  # ephemeral (TF_VAR_*), written write-only; bump the *_version to (re)write.
  openai_api_key         = var.openai_api_key
  openai_api_key_version = var.openai_api_key_version

  create_config_server_git_secrets      = var.create_config_server_git_secrets
  config_server_git_username            = var.config_server_git_username
  config_server_git_password            = var.config_server_git_password
  config_server_git_credentials_version = var.config_server_git_credentials_version

  # Prod: 7-day recovery window for accidental deletes.
  secret_recovery_window_in_days = 7

  # technical-spec.md#irsa-roles — petclinic-prod-eso-role for external-secrets/external-secrets-sa
  oidc_provider_arn = module.eks.oidc_provider_arn

  tags = merge(var.additional_tags, { Component = "secrets" })
}

# Remaining module calls are added by their owning epics:
#   module "dns"           -> E-6  (terraform/modules/dns)
#   module "observability" -> E-11 (terraform/modules/observability)
#   module "karpenter"     -> E-14 (terraform/modules/karpenter)
