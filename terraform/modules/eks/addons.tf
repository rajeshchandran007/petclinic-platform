# EKS managed add-ons with pinned versions (PETPLAT-84).
#
# vpc-cni and kube-proxy are installed before the node group so nodes become
# Ready as soon as they join. coredns and the EBS CSI driver run as Deployments
# and need nodes to schedule on, so they are installed after the node group.
# Upgrade procedure: docs/runbook.md#procedure-upgrade-eks-add-on-versions

locals {
  addons_before_compute = {
    "vpc-cni"    = { service_account_role_arn = null }
    "kube-proxy" = { service_account_role_arn = null }
  }

  addons_after_compute = {
    "coredns"            = { service_account_role_arn = null }
    "aws-ebs-csi-driver" = { service_account_role_arn = aws_iam_role.ebs_csi.arn }
  }
}

resource "aws_eks_addon" "before_compute" {
  for_each = local.addons_before_compute

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.key
  addon_version            = var.addon_versions[each.key]
  service_account_role_arn = each.value.service_account_role_arn

  # EKS bootstraps self-managed copies of these at cluster creation; OVERWRITE
  # lets the managed add-on take them over.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.key}"
  })
}

resource "aws_eks_addon" "after_compute" {
  for_each = local.addons_after_compute

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.key
  addon_version            = var.addon_versions[each.key]
  service_account_role_arn = each.value.service_account_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.key}"
  })

  depends_on = [aws_eks_node_group.this]
}

################################################################################
# IRSA role for the EBS CSI driver controller (technical-spec.md#irsa-roles)
################################################################################

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
