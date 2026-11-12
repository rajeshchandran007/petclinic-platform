variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "tags" {
  description = "Additional tags merged into the required Project/Environment/ManagedBy tags."
  type        = map(string)
  default     = {}
}

################################################################################
# Networking
################################################################################

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (at least 2 AZs)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A DB subnet group needs subnets in at least 2 availability zones."
  }
}

variable "security_group_id" {
  description = "RDS security group ID (allows 3306 from the EKS node SG only; owned by the vpc module)."
  type        = string
}

################################################################################
# Engine / instance
################################################################################

variable "engine_version" {
  description = "MySQL engine version (major or major.minor, e.g. \"8.0\" or \"8.4\"). The parameter group family is derived from the major version."
  type        = string
  default     = "8.0"

  validation {
    condition     = can(regex("^8\\.[04](\\.\\d+)?$", var.engine_version))
    error_message = "engine_version must be MySQL 8.0 or 8.4 (e.g. \"8.0\", \"8.0.43\", \"8.4\")."
  }
}

variable "instance_class" {
  description = "RDS instance class (db.t4g.micro is free-tier eligible, ARM/Graviton)."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Name of the shared application database created on the instance."
  type        = string
  default     = "petclinic"
}

variable "multi_az" {
  description = "Deploy a synchronous standby in a second AZ. False in both envs for cost; enable for real production workloads."
  type        = bool
  default     = false
}

################################################################################
# Storage
################################################################################

variable "allocated_storage" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB for MySQL."
  }
}

variable "max_allocated_storage" {
  description = "Upper limit in GB for storage autoscaling. Must be greater than allocated_storage to enable autoscaling (0 disables it). Storage never shrinks, so keep the ceiling modest."
  type        = number
  default     = 40

  validation {
    condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= 20
    error_message = "max_allocated_storage must be 0 (disabled) or >= 20."
  }
}

variable "storage_type" {
  description = "Storage type (gp2 for free tier, gp3 for production)."
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be one of gp2, gp3, io1, io2."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for storage encryption. Null uses the AWS-managed aws/rds key."
  type        = string
  default     = null
}

################################################################################
# Backup / lifecycle
################################################################################

variable "backup_retention_period" {
  description = "Automated backup retention in days (7 dev, 30 prod)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Daily backup window (UTC). Must not overlap maintenance_window."
  type        = string
  default     = "19:00-20:00" # 00:30-01:30 IST
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)."
  type        = string
  default     = "sun:20:30-sun:21:30" # Mon 02:00-03:00 IST
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is deleted (true dev, false prod)."
  type        = bool
  default     = true
}

variable "delete_automated_backups" {
  description = "Delete automated backups when the instance is deleted (true dev, false prod)."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent the instance from being deleted."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of during the maintenance window."
  type        = bool
  default     = false
}

################################################################################
# Credentials
################################################################################

variable "master_username" {
  description = "Master username for the instance."
  type        = string
  default     = "petclinic"
}

variable "master_password_length" {
  description = "Length of the generated master password (minimum 16)."
  type        = number
  default     = 24

  validation {
    condition     = var.master_password_length >= 16 && var.master_password_length <= 41
    error_message = "master_password_length must be between 16 and 41 (MySQL limit)."
  }
}

variable "master_password_version" {
  description = "Increment to generate a new master password and write it to both RDS and Secrets Manager (write-only rotation trigger)."
  type        = number
  default     = 1
}

variable "secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps a deleted secret recoverable (0 = delete immediately, allows instant re-create in dev)."
  type        = number
  default     = 7

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "require_secure_transport" {
  description = "Reject non-TLS client connections (require_secure_transport parameter)."
  type        = bool
  default     = true
}

################################################################################
# Logging
################################################################################

variable "enabled_cloudwatch_logs_exports" {
  description = "RDS log types to export to CloudWatch (error, general, slowquery, audit)."
  type        = list(string)
  default     = ["error"]

  validation {
    condition     = alltrue([for l in var.enabled_cloudwatch_logs_exports : contains(["error", "general", "slowquery", "audit", "iam-db-auth-error"], l)])
    error_message = "Valid log types: error, general, slowquery, audit, iam-db-auth-error."
  }
}

variable "log_retention_in_days" {
  description = "Retention for exported RDS CloudWatch log groups."
  type        = number
  default     = 7
}
