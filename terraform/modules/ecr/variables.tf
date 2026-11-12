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

variable "service_names" {
  description = "Service names; one ECR repository petclinic-{env}/{service} is created per entry."
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0 && length(var.service_names) == length(distinct(var.service_names))
    error_message = "service_names must be a non-empty list without duplicates."
  }

  validation {
    condition     = alltrue([for s in var.service_names : can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", s))])
    error_message = "Each service name must be lowercase alphanumerics separated by '.', '_' or '-' (ECR repository naming rules)."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability for every repository: MUTABLE for dev (re-push same tag), IMMUTABLE for prod (deployed tags cannot be overwritten)."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be \"MUTABLE\" or \"IMMUTABLE\"."
  }
}

variable "max_tagged_image_count" {
  description = "Lifecycle policy: number of most recent tagged images to keep per repository."
  type        = number
  default     = 10

  validation {
    condition     = var.max_tagged_image_count >= 1 && floor(var.max_tagged_image_count) == var.max_tagged_image_count
    error_message = "max_tagged_image_count must be a positive integer."
  }
}

variable "untagged_image_expiry_days" {
  description = "Lifecycle policy: days after push before untagged images expire."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_expiry_days >= 1 && floor(var.untagged_image_expiry_days) == var.untagged_image_expiry_days
    error_message = "untagged_image_expiry_days must be a positive integer."
  }
}

variable "encryption_type" {
  description = "Repository encryption at rest: AES256 (ECR-managed, spec default) or KMS."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be \"AES256\" or \"KMS\"."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN, required when encryption_type = \"KMS\"; must be null for AES256."
  type        = string
  default     = null

  validation {
    condition     = (var.encryption_type == "KMS") == (var.kms_key_arn != null)
    error_message = "kms_key_arn must be set when encryption_type is \"KMS\" and left null when it is \"AES256\"."
  }

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:{region}:{account}:key/{id})."
  }
}

variable "force_delete" {
  description = "Allow deleting repositories that still contain images. Keep false unless tearing down an environment."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged into the required Project/Environment/ManagedBy tags."
  type        = map(string)
  default     = {}
}
