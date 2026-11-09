provider "aws" {
  region = var.aws_region

  # Required tags (Project, Environment, ManagedBy) are applied to every
  # taggable resource via default_tags. See technical-spec.md#required-tags-all-aws-resources.
  default_tags {
    tags = local.common_tags
  }
}
