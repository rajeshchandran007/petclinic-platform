output "zone_id" {
  description = "Route 53 hosted zone ID."
  value       = local.zone_id
}

output "zone_name_servers" {
  description = "Name servers to configure at the domain registrar (NS delegation). Empty when using an existing zone."
  value       = try(aws_route53_zone.this[0].name_servers, [])
}

output "certificate_arn" {
  description = "ACM certificate ARN for the Ingress (alb.ingress.kubernetes.io/certificate-arn). Issued when wait_for_certificate_validation = true; otherwise it may still be PENDING_VALIDATION and the ALB HTTPS listener will fail until ACM issues it."
  value       = var.wait_for_certificate_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "certificate_domain_name" {
  description = "Primary domain on the certificate (*.{domain})."
  value       = aws_acm_certificate.this.domain_name
}

output "app_fqdn" {
  description = "Application hostname ({record_name}.{domain})."
  value       = local.record_fqdn
}

output "app_record_created" {
  description = "Whether the alias record to the ALB exists (alb_name was set)."
  value       = length(aws_route53_record.app) > 0
}
