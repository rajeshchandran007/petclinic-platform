# Module: ecr
# ECR private repositories per service with lifecycle policies, scan-on-push
# and per-environment tag immutability (E-4: PETPLAT-18, PETPLAT-19).
# See docs/technical-spec.md#ecr-container-registry and #module-ecr.

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )

  service_names = toset(var.service_names)

  # The two rules select disjoint image sets, so their priority order does not
  # change behaviour (the spec's single tagStatus="any" rule would count
  # untagged images toward the limit and never age them out):
  #   1. Untagged images (build leftovers, overwritten MUTABLE tags) expire
  #      after N days.
  #   2. Of the tagged images, only the most recent N are kept. In IMMUTABLE
  #      prod this also bounds how far back a rollback can go.
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_tagged_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_tagged_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

################################################################################
# Repositories (PETPLAT-18)
################################################################################

resource "aws_ecr_repository" "this" {
  for_each = local.service_names

  # petclinic-{env}/{service}, e.g. petclinic-dev/api-gateway
  name                 = "${local.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  # Spec: AES256 (ECR-managed keys). KMS is supported via encryption_type/kms_key_arn.
  # Encryption settings are fixed at creation: changing them on an existing
  # repository forces replacement (repo and images deleted). Check the plan.
  #checkov:skip=CKV_AWS_136:AES256 is the spec default (technical-spec.md#repository-configuration); KMS is opt-in via var.encryption_type.
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}/${each.key}"
    Service = each.key
  })
}

################################################################################
# Lifecycle policies (PETPLAT-19)
################################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = local.lifecycle_policy
}
