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

variable "vpc_cidr" {
  description = "CIDR block for the VPC (dev: 10.0.0.0/16, prod: 10.1.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone (same order as availability_zones)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "public_subnet_cidrs must contain at least 2 valid IPv4 CIDR blocks."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets (e.g. [\"ap-south-1a\", \"ap-south-1b\"])."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must contain at least 2 distinct AZs."
  }
}

variable "cluster_name" {
  description = "EKS cluster name used in the kubernetes.io/cluster/<name> subnet tag. Defaults to {project}-{environment}."
  type        = string
  default     = null
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Traffic captured by VPC Flow Logs: ACCEPT, REJECT or ALL. REJECT keeps ingestion cost low."
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention (days) for VPC Flow Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a valid CloudWatch retention value (1-365)."
  }
}

variable "tags" {
  description = "Additional tags merged into the required Project/Environment/ManagedBy tags."
  type        = map(string)
  default     = {}
}
