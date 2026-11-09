# Managed ARM64 (Graviton) node group in the public subnets (PETPLAT-13).
#
# A launch template is used so the nodes carry the VPC module's node security
# group, get an encrypted gp3 root volume, and enforce IMDSv2.

################################################################################
# Node IAM role
################################################################################

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

################################################################################
# Launch template
################################################################################

resource "aws_launch_template" "node" {
  name_prefix            = "${local.name_prefix}-eks-node-"
  description            = "EKS managed node group nodes for ${local.cluster_name}"
  update_default_version = true

  # Replaces the EKS-managed cluster SG on the nodes; the VPC module's node SG
  # carries all rules needed for control-plane, node-to-node and ALB traffic.
  vpc_security_group_ids = [var.node_sg_id]

  block_device_mappings {
    device_name = "/dev/xvda" # root device for the AL2023 EKS AMIs

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = var.node_imds_hop_limit
  }

  monitoring {
    enabled = false # detailed monitoring is billed; basic 5-minute metrics are enough
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-eks-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-eks-node-root" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-eks-node-eni" })
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-lt"
  })
}

################################################################################
# Managed node group
################################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = merge(
    {
      "environment" = var.environment
      "managed-by"  = "terraform"
    },
    var.node_labels,
  )

  dynamic "taint" {
    for_each = var.node_taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nodes"
  })

  lifecycle {
    # Autoscalers (Karpenter / HPA-driven scale-ups) own desired_size after creation.
    ignore_changes = [scaling_config[0].desired_size]
  }

  # vpc-cni and kube-proxy must be in place before nodes join, otherwise nodes
  # stay NotReady; the IAM attachments must exist before nodes bootstrap.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]
}
