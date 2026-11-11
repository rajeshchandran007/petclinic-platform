# kubectl access via EKS access entries (PETPLAT-14).
#
# The IAM principal running Terraform is granted cluster-admin automatically
# (unless it is the account root user). Additional admins are added through
# var.cluster_admin_principal_arns. The account root user gets an entry only
# when var.grant_root_cluster_admin is explicitly enabled (console visibility).
# See docs/runbook.md for the procedure.

data "aws_iam_session_context" "current" {
  # Resolves an assumed-role session ARN to the underlying IAM role ARN, which is
  # what an access entry must reference.
  arn = data.aws_caller_identity.current.arn
}

locals {
  deployer_principal_arn = data.aws_iam_session_context.current.issuer_arn
  deployer_is_root       = endswith(local.deployer_principal_arn, ":root")
  root_principal_arn     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"

  cluster_admin_principal_arns = toset(concat(
    var.cluster_admin_principal_arns,
    var.grant_deployer_cluster_admin && !local.deployer_is_root ? [local.deployer_principal_arn] : [],
    var.grant_root_cluster_admin ? [local.root_principal_arn] : [],
  ))
}

resource "aws_eks_access_entry" "admin" {
  for_each = local.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = local.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
