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
