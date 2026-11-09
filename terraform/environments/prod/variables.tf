variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "project" {
  description = "Project name, used as the resource name prefix (petclinic-{env}-{resource})."
  type        = string
  default     = "petclinic"
}

variable "additional_tags" {
  description = "Extra tags merged into the common tags applied to every resource."
  type        = map(string)
  default     = {}
}
