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
# Zone
################################################################################

variable "domain_name" {
  description = "Domain for the public hosted zone (e.g. example.com). The certificate covers *.{domain_name}."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}\\.?$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name such as example.com."
  }
}

variable "create_hosted_zone" {
  description = "Create the Route 53 hosted zone. Set false to look up an existing public zone for domain_name (e.g. prod reusing the dev-created zone)."
  type        = bool
  default     = true
}

################################################################################
# Certificate
################################################################################

variable "certificate_subject_alternative_names" {
  description = "Extra names on the ACM certificate besides *.{domain_name} (e.g. the apex domain)."
  type        = list(string)
  default     = []
}

variable "wait_for_certificate_validation" {
  description = "Wait for ACM to issue the certificate (aws_acm_certificate_validation). Requires the zone's NS records to be delegated at the registrar, otherwise apply blocks until the timeout."
  type        = bool
  default     = true
}

variable "certificate_validation_timeout" {
  description = "How long to wait for ACM certificate issuance."
  type        = string
  default     = "45m"
}

################################################################################
# Alias record
################################################################################

variable "record_name" {
  description = "Host label for the application record: petclinic-dev (dev) or petclinic (prod) -> {record_name}.{domain_name}."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.record_name))
    error_message = "record_name must be a single lowercase DNS label."
  }
}

variable "alb_name" {
  description = "Name of the ALB created by the AWS Load Balancer Controller (alb.ingress.kubernetes.io/load-balancer-name). Null skips the alias record — set it after the Ingress has created the ALB."
  type        = string
  default     = null
}
