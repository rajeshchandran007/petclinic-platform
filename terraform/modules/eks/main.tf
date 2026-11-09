# Module: eks
# EKS control plane, cluster IAM role, control-plane logging and the IAM OIDC
# provider used for IRSA (PETPLAT-12).
#
# Related files in this module:
#   node_group.tf - managed ARM node group + node IAM role (PETPLAT-13)
#   access.tf     - EKS access entries for cluster admins (PETPLAT-14)
#   addons.tf     - managed add-ons + EBS CSI IRSA role (PETPLAT-84)
#
# Contract: docs/technical-spec.md#module-eks

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix # petclinic-{env}; must match the VPC subnet tag

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  # Issuer URL without the scheme, as used in IRSA trust-policy condition keys.
  oidc_provider_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

################################################################################
# Cluster IAM role
################################################################################

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

################################################################################
# Control-plane logs
# Pre-created so Terraform owns the retention; EKS would otherwise create the
# group itself with "never expire".
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts at rest by default; CMK omitted for cost (learning project)
  #checkov:skip=CKV_AWS_338:Short retention is intentional to minimise cost
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-control-plane-logs"
  })
}

################################################################################
# EKS cluster
################################################################################

resource "aws_eks_cluster" "this" {
  #checkov:skip=CKV_AWS_39:Public endpoint is required by the all-public design (ADR-0001); restricted via public_access_cidrs
  #checkov:skip=CKV_AWS_58:EKS envelope-encrypts all Kubernetes API data by default (1.28+); a CMK can be supplied via kms_key_arn
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = var.cluster_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = true
    endpoint_private_access = true # nodes reach the API server over in-VPC ENIs
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Admin access is granted through explicit, Terraform-managed access entries
    # (access.tf) instead of the implicit, invisible creator grant.
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Avoid the automatic switch to extended support, which bills the control
  # plane at 6x the standard rate once a version leaves standard support.
  upgrade_policy {
    support_type = "STANDARD"
  }

  dynamic "encryption_config" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]

    content {
      resources = ["secrets"]

      provider {
        key_arn = encryption_config.value
      }
    }
  }

  tags = merge(local.tags, {
    Name = local.cluster_name
  })

  lifecycle {
    precondition {
      condition     = length(local.cluster_admin_principal_arns) > 0
      error_message = "No EKS cluster admin principal. Terraform is running as the AWS account root user, which is never granted cluster access. Run Terraform as an IAM user or role, or set cluster_admin_principal_arns to at least one IAM user/role ARN."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

################################################################################
# IAM OIDC provider (IRSA)
################################################################################

resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-oidc"
  })
}
