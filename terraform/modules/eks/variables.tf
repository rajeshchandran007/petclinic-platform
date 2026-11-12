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
# Cluster
################################################################################

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane. Must be a version in EKS standard support."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version)) && tonumber(split(".", var.cluster_version)[1]) >= 29
    error_message = "cluster_version must be a Kubernetes minor version string, 1.29 or later (e.g. \"1.35\")."
  }
}

variable "subnet_ids" {
  description = "Public subnet IDs (at least 2 AZs) for the control-plane ENIs and the node group."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnet_ids in at least 2 availability zones."
  }
}

variable "cluster_sg_id" {
  description = "Security group ID attached to the EKS control-plane ENIs (from the vpc module)."
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID attached to the worker nodes (from the vpc module)."
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (operator IPs, e.g. [\"203.0.113.10/32\"]). Required; 0.0.0.0/0 is rejected."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "cluster_endpoint_public_access_cidrs must contain at least one valid IPv4 CIDR."
  }

  validation {
    condition     = alltrue([for c in var.cluster_endpoint_public_access_cidrs : !can(regex("/0$", c))])
    error_message = "cluster_endpoint_public_access_cidrs must not contain 0.0.0.0/0 (or any /0). Use your operator IP(s), e.g. [\"203.0.113.10/32\"]."
  }
}

variable "cluster_log_types" {
  description = "Control-plane log types sent to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]

  validation {
    condition     = alltrue([for t in var.cluster_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "cluster_log_types may only contain api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention (days) for EKS control-plane logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.cluster_log_retention_days)
    error_message = "cluster_log_retention_days must be a valid CloudWatch retention value (1-365)."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for Kubernetes secrets envelope encryption. null uses the EKS default encryption."
  type        = string
  default     = null
}

################################################################################
# Access (PETPLAT-14)
################################################################################

variable "grant_deployer_cluster_admin" {
  description = "Create a cluster-admin access entry for the IAM principal running Terraform (ignored when that principal is the account root user)."
  type        = bool
  default     = true
}

variable "grant_root_cluster_admin" {
  description = "Create a cluster-admin access entry for the AWS account root user (arn:aws:iam::<account>:root). Opt-in only: lets the root user see cluster resources in the EKS console. Keep false in prod."
  type        = bool
  default     = false
}

variable "cluster_admin_principal_arns" {
  description = "Additional IAM user/role ARNs granted AmazonEKSClusterAdminPolicy through EKS access entries."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cluster_admin_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(user|role)/.+$", a))])
    error_message = "cluster_admin_principal_arns must contain IAM user or role ARNs (not the root user or assumed-role session ARNs)."
  }
}

################################################################################
# Node group (PETPLAT-13)
################################################################################

variable "node_instance_types" {
  description = "Instance types for the managed node group (ARM64/Graviton to match the AMI type)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group. AL2 AMIs are not published for Kubernetes 1.33+, so AL2023 is used."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_capacity_type" {
  description = "Capacity type for the node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes at creation (later owned by autoscalers)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size (GB) per node (gp3, encrypted)."
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size must be at least 20 GB (EKS AMI minimum)."
  }
}

variable "node_imds_hop_limit" {
  description = "IMDSv2 PUT response hop limit. 1 blocks pods (non-hostNetwork) from reaching instance metadata, forcing them onto IRSA."
  type        = number
  default     = 1

  validation {
    condition     = var.node_imds_hop_limit >= 1 && var.node_imds_hop_limit <= 2
    error_message = "node_imds_hop_limit must be 1 or 2."
  }
}

variable "node_labels" {
  description = "Extra Kubernetes labels for the nodes (merged with environment and managed-by)."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints applied to the nodes."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []

  validation {
    condition     = alltrue([for t in var.node_taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)])
    error_message = "node_taints effect must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
}

################################################################################
# Add-ons (PETPLAT-84)
################################################################################

variable "addon_versions" {
  description = "Pinned EKS add-on versions. Must be compatible with cluster_version; list with `aws eks describe-addon-versions --kubernetes-version <v> --addon-name <name>`."
  type = object({
    vpc-cni            = string
    kube-proxy         = string
    coredns            = string
    aws-ebs-csi-driver = string
  })
  default = {
    "vpc-cni"            = "v1.22.4-eksbuild.10"
    "kube-proxy"         = "v1.35.3-eksbuild.64"
    "coredns"            = "v1.13.2-eksbuild.68"
    "aws-ebs-csi-driver" = "v1.67.2-eksbuild.1"
  }

  validation {
    condition     = alltrue([for v in values(var.addon_versions) : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", v))])
    error_message = "addon_versions must be exact versions like v1.22.4-eksbuild.10 (no \"latest\")."
  }
}

################################################################################
# AWS Load Balancer Controller IRSA (PETPLAT-29)
################################################################################

variable "enable_lb_controller_irsa" {
  description = "Create the IRSA role + IAM policy for the AWS Load Balancer Controller (kube-system/aws-load-balancer-controller)."
  type        = bool
  default     = true
}

variable "lb_controller_version" {
  description = "AWS Load Balancer Controller app version whose upstream IAM policy is vendored in policies/. Must match the Helm chart installed by scripts/install-lb-controller.sh."
  type        = string
  default     = "v3.6.2"

  validation {
    condition     = fileexists("${path.module}/policies/aws-load-balancer-controller-${var.lb_controller_version}.json")
    error_message = "No vendored IAM policy for this version. Download docs/install/iam_policy.json from the matching kubernetes-sigs/aws-load-balancer-controller tag into policies/."
  }
}

variable "lb_controller_protected_security_group_ids" {
  description = "Extra Terraform-managed security groups (e.g. RDS, ALB) the Load Balancer Controller is explicitly denied from modifying. The cluster and node SGs are always protected."
  type        = list(string)
  default     = []
}
