# Module: rds
# RDS MySQL instance, subnet/parameter groups, credentials secret (E-5)
#
# PETPLAT-22: RDS MySQL instance (single shared `petclinic` database)
# PETPLAT-23: Master credentials generated with random_password and stored in
#             Secrets Manager as `petclinic/{env}/rds-credentials`
#
# See docs/technical-spec.md#rds-database and #module-rds.
#
# Credentials never touch Terraform state: the password is an *ephemeral*
# random_password and is passed only to write-only arguments (`password_wo`,
# `secret_string_wo`), which Terraform does not persist in state or plan files.
# Rotate by bumping var.master_password_version.

locals {
  name_prefix   = "${var.project}-${var.environment}"
  identifier    = "${local.name_prefix}-mysql"
  secret_name   = "${var.project}/${var.environment}/rds-credentials"
  engine_major  = join(".", slice(split(".", var.engine_version), 0, 2))
  param_family  = "mysql${local.engine_major}"
  param_name_sf = replace(local.engine_major, ".", "-")

  # Required tags last so callers cannot override them.
  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

################################################################################
# Master credentials (PETPLAT-23)
################################################################################

# Ephemeral: the generated value exists only for the duration of a plan/apply
# and is never written to state.
ephemeral "random_password" "master" {
  length      = var.master_password_length
  special     = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
  # RDS rejects '/', '@', '"' and spaces in the master password.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  #checkov:skip=CKV2_AWS_57:Rotation not configured; rotate manually via master_password_version (learning project)
  #checkov:skip=CKV_AWS_149:Encrypted with the AWS-managed aws/secretsmanager key per technical-spec.md#secrets
  name                    = local.secret_name
  description             = "RDS MySQL master credentials for ${local.identifier} (JSON: username, password)"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.tags, { Name = local.secret_name })
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id

  secret_string_wo = jsonencode({
    username = var.master_username
    password = ephemeral.random_password.master.result
  })
  secret_string_wo_version = var.master_password_version
}

################################################################################
# Networking
################################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-db-subnets"
  description = "Subnets for ${local.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-subnets" })
}

################################################################################
# Parameter group (technical-spec.md#parameter-group)
################################################################################

resource "aws_db_parameter_group" "this" {
  # name_prefix (not name) so create_before_destroy can create the replacement
  # group on a family change (e.g. 8.0 -> 8.4) without a name collision.
  name_prefix = "${local.name_prefix}-mysql${local.param_name_sf}-"
  family      = local.param_family
  description = "${local.identifier} parameters (utf8mb4, TLS required)"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Encryption in transit: reject non-TLS connections. MySQL Connector/J
  # defaults to sslMode=PREFERRED, so the plain JDBC URL negotiates TLS.
  parameter {
    name  = "require_secure_transport"
    value = var.require_secure_transport ? "1" : "0"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql${local.param_name_sf}" })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# CloudWatch log groups for exported RDS logs (created up front so they get a
# retention policy instead of RDS auto-creating them with "never expire")
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:AWS-managed encryption is sufficient for RDS error logs (learning project)
  #checkov:skip=CKV_AWS_338:Short retention is intentional for cost (learning project)
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${local.identifier}/${each.value}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.tags, { Name = "${local.identifier}-${each.value}" })
}

################################################################################
# RDS instance (PETPLAT-22)
################################################################################

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_118:Enhanced monitoring disabled for cost (learning project)
  #checkov:skip=CKV_AWS_353:Performance Insights not used on db.t4g.micro (learning project)
  #checkov:skip=CKV_AWS_157:Multi-AZ is configurable; disabled in both envs for cost (technical-spec.md#instance-configuration)
  #checkov:skip=CKV_AWS_293:Deletion protection is configurable per environment
  #checkov:skip=CKV2_AWS_60:copy_tags_to_snapshot is enabled; check misfires on variable values
  identifier = local.identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Single shared database for customers, visits and vets services.
  db_name  = var.db_name
  username = var.master_username

  # Write-only: never stored in state. Applied on create and whenever
  # master_password_version changes (same version drives the secret above).
  password_wo         = ephemeral.random_password.master.result
  password_wo_version = var.master_password_version

  port                   = 3306
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  # Subnets are public (ADR-0001) but the instance gets no public IP; access is
  # only via the RDS SG (3306 from EKS node SG).
  publicly_accessible = false
  multi_az            = var.multi_az

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final"
  delete_automated_backups  = var.delete_automated_backups
  deletion_protection       = var.deletion_protection

  auto_minor_version_upgrade      = true
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = merge(local.tags, { Name = local.identifier })

  # The secret is written first so the DB is never created with a password that
  # exists nowhere else. Caveat: the ephemeral password is regenerated on every
  # run, so if an apply fails AFTER the secret is written but BEFORE the DB is
  # created, the next apply creates the DB with a different password than the
  # secret. Recovery: bump master_password_version and apply again — both
  # write-only values are then rewritten from the same run.
  # See docs/database-initialization.md#credentials.
  depends_on = [
    aws_secretsmanager_secret_version.rds_credentials,
    aws_cloudwatch_log_group.this,
  ]
}
