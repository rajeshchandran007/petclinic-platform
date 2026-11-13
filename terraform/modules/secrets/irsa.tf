################################################################################
# IRSA role for External Secrets Operator (PETPLAT-37)
# technical-spec.md#irsa-roles: petclinic-{env}-eso-role
#   -> external-secrets/external-secrets-sa
#
# The ClusterSecretStore (k8s/base/external-secrets/cluster-secret-store.yaml)
# authenticates with auth.jwt.serviceAccountRef -> external-secrets-sa, whose
# eks.amazonaws.com/role-arn annotation points at this role.
#
# Least privilege: read-only (GetSecretValue, DescribeSecret) and scoped to this
# environment's prefix petclinic/{env}/* rather than the spec's petclinic/*.
# Dev and prod share one AWS account, so petclinic/* would let the dev cluster
# read prod secrets. petclinic/{env}/* still covers rds-credentials (rds module)
# and every secret in this module.
################################################################################

locals {
  # "arn:aws:iam::123456789012:oidc-provider/oidc.eks.<region>.amazonaws.com/id/XXXX"
  # -> "oidc.eks.<region>.amazonaws.com/id/XXXX"
  oidc_provider_host = element(split("oidc-provider/", var.oidc_provider_arn), 1)

  eso_secret_arn_pattern = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_prefix}/*"
}

data "aws_iam_policy_document" "eso_assume" {
  statement {
    sid     = "EsoServiceAccountWebIdentity"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:${var.eso_namespace}:${var.eso_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name_prefix}-eso-role"
  description        = "IRSA role for External Secrets Operator (${var.eso_namespace}/${var.eso_service_account}) in ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-eso-role" })
}

data "aws_iam_policy_document" "eso_read_secrets" {
  statement {
    sid    = "ReadEnvironmentSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [local.eso_secret_arn_pattern]
  }

  # Only needed if a secret is moved to a customer-managed KMS key. The default
  # aws/secretsmanager key needs no extra grant. kms:ViaService limits use of the
  # key to decrypts made by Secrets Manager on ESO's behalf.
  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptSecretsViaSecretsManager"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arns

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "eso_read_secrets" {
  name   = "${local.name_prefix}-eso-read-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read_secrets.json
}
