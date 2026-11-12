# Module: dns
# Route 53 hosted zone, ACM certificate, ALB alias record (E-6)
#
# PETPLAT-28: hosted zone + wildcard ACM certificate (DNS-validated)
# PETPLAT-31: A (alias) record -> ALB created by the AWS Load Balancer Controller
#
# See docs/technical-spec.md#dns-and-ingress and #module-dns.
#
# Two-phase apply for the alias record: the ALB only exists after the Ingress
# (k8s/base/ingress/ingress.yaml) is applied, so the record is created only when
# var.alb_name is set. The Ingress pins the ALB name via the
# alb.ingress.kubernetes.io/load-balancer-name annotation (petclinic-{env}-alb).

locals {
  name_prefix = "${var.project}-${var.environment}"
  domain_name = trimsuffix(var.domain_name, ".")
  record_fqdn = "${var.record_name}.${local.domain_name}"
  zone_id     = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id

  # Required tags last so callers cannot override them.
  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

################################################################################
# Hosted zone (PETPLAT-28)
################################################################################

resource "aws_route53_zone" "this" {
  #checkov:skip=CKV2_AWS_38:DNSSEC not enabled (learning project; requires KMS key in us-east-1 + registrar DS record)
  #checkov:skip=CKV2_AWS_39:Query logging not enabled (learning project; requires log group in us-east-1)
  count = var.create_hosted_zone ? 1 : 0

  name          = local.domain_name
  comment       = "petclinic public zone (managed by ${local.name_prefix})"
  force_destroy = false

  tags = merge(local.tags, { Name = local.domain_name })

  # The zone is shared (prod looks it up) and its NS records are delegated at the
  # registrar; re-creating it yields new name servers and breaks DNS. To tear down
  # an env deliberately: terraform state rm 'module.dns.aws_route53_zone.this[0]'.
  lifecycle {
    prevent_destroy = true
  }
}

# Use an existing zone (e.g. prod reusing the zone created by dev) instead of
# creating a second, undelegated zone for the same domain.
data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1

  name         = local.domain_name
  private_zone = false
}

################################################################################
# ACM certificate — *.{domain}, DNS validation (technical-spec.md#acm-certificate)
################################################################################

resource "aws_acm_certificate" "this" {
  domain_name               = "*.${local.domain_name}"
  subject_alternative_names = var.certificate_subject_alternative_names
  validation_method         = "DNS"
  key_algorithm             = "RSA_2048"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-wildcard-cert" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  # Keyed by domain_name (known at plan time; resource_record_name is not).
  # ACM issues the same CNAME for *.{domain} and {domain}, so adding the apex as a
  # SAN yields two resources writing one record — allow_overwrite tolerates this.
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# Blocks until ACM reports ISSUED. That only happens once the hosted zone's
# name servers are delegated at the domain registrar (see output name_servers).
resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_certificate_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]

  timeouts {
    create = var.certificate_validation_timeout
  }
}

################################################################################
# Alias record -> ALB (PETPLAT-31)
################################################################################

data "aws_lb" "ingress" {
  count = var.alb_name == null ? 0 : 1

  name = var.alb_name
}

resource "aws_route53_record" "app" {
  count = var.alb_name == null ? 0 : 1

  zone_id = local.zone_id
  name    = local.record_fqdn
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress[0].dns_name
    zone_id                = data.aws_lb.ingress[0].zone_id
    evaluate_target_health = true
  }
}
