################################################################################
# IRSA role for the AWS Load Balancer Controller (PETPLAT-29)
# technical-spec.md#irsa-roles: petclinic-{env}-lb-controller-role
#   -> kube-system/aws-load-balancer-controller
#
# The controller itself is installed with Helm by scripts/install-lb-controller.sh.
################################################################################

locals {
  lb_controller_namespace       = "kube-system"
  lb_controller_service_account = "aws-load-balancer-controller"
}

# Upstream policy published with the controller release, vendored verbatim so the
# permissions always match the installed chart version (var.lb_controller_version).
# Several statements use Resource "*" because the corresponding EC2/ELB Describe*
# and Create* APIs do not support resource-level permissions; mutating actions are
# constrained by the elbv2.k8s.aws/cluster tag conditions in the upstream document.
resource "aws_iam_policy" "lb_controller" {
  #checkov:skip=CKV_AWS_355:Upstream AWS LBC policy; Describe*/Create* APIs require Resource "*"
  #checkov:skip=CKV_AWS_290:Upstream AWS LBC policy; write actions are tag-conditioned
  #checkov:skip=CKV_AWS_289:Upstream AWS LBC policy; permissions management is tag-conditioned
  count = var.enable_lb_controller_irsa ? 1 : 0

  name        = "${local.name_prefix}-lb-controller-policy"
  description = "AWS Load Balancer Controller ${var.lb_controller_version} permissions for ${local.name_prefix}"
  policy      = file("${path.module}/policies/aws-load-balancer-controller-${var.lb_controller_version}.json")

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lb-controller-policy"
  })
}

data "aws_iam_policy_document" "lb_controller_assume" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:${local.lb_controller_namespace}:${local.lb_controller_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  role       = aws_iam_role.lb_controller[0].name
  policy_arn = aws_iam_policy.lb_controller[0].arn
}

################################################################################
# Guardrails on top of the upstream policy (explicit Deny always wins)
#
# 1. The upstream policy allows ec2:Authorize/RevokeSecurityGroupIngress on
#    Resource "*" without conditions. Deny any rule changes on the Terraform-
#    managed perimeter SGs (cluster, node, plus e.g. RDS and ALB SGs passed by
#    the environment). The Ingress pins the ALB SG and sets
#    manage-backend-security-group-rules: "false", so the controller never needs
#    to change these.
# 2. Dev and prod share one AWS account. Deny mutating any ELB/SG resource the
#    controller tagged for a *different* cluster (tag present and != this cluster).
################################################################################

locals {
  lb_controller_protected_sg_arns = [
    for id in distinct(concat([var.cluster_sg_id, var.node_sg_id], var.lb_controller_protected_security_group_ids)) :
    "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/${id}"
  ]
}

data "aws_iam_policy_document" "lb_controller_guardrails" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  statement {
    sid    = "DenyPerimeterSecurityGroupChanges"
    effect = "Deny"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = local.lb_controller_protected_sg_arns
  }

  statement {
    sid    = "DenyOtherClustersResources"
    effect = "Deny"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [aws_eks_cluster.this.name]
    }
  }
}

resource "aws_iam_role_policy" "lb_controller_guardrails" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  name   = "${local.name_prefix}-lb-controller-guardrails"
  role   = aws_iam_role.lb_controller[0].id
  policy = data.aws_iam_policy_document.lb_controller_guardrails[0].json
}
