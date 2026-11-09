variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "dev"

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

variable "vpc_cidr" {
  description = "VPC CIDR block (technical-spec.md#cidr-allocation)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ (same order as availability_zones)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the public subnets."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

################################################################################
# EKS (technical-spec.md#eks-cluster)
################################################################################

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be in EKS standard support)."
  type        = string
  default     = "1.35"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Required: set your operator IP(s) as /32 in terraform.tfvars (0.0.0.0/0 is rejected by the eks module)."
  type        = list(string)
}

variable "eks_cluster_admin_principal_arns" {
  description = "Additional IAM user/role ARNs granted cluster-admin (the IAM principal running Terraform is added automatically unless it is root)."
  type        = list(string)
  default     = []
}
