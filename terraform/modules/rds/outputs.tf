output "endpoint" {
  description = "RDS endpoint hostname (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port (3306)."
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = aws_db_instance.this.arn
}

output "db_instance_resource_id" {
  description = "RDS resource ID (used for IAM database authentication policies)."
  value       = aws_db_instance.this.resource_id
}

output "db_name" {
  description = "Shared application database name."
  value       = aws_db_instance.this.db_name
}

output "jdbc_url" {
  description = "JDBC URL for SPRING_DATASOURCE_URL (technical-spec.md#connection-string-format)."
  value       = "jdbc:mysql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}

output "secret_arn" {
  description = "Secrets Manager ARN of the RDS credentials secret (for External Secrets Operator)."
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "secret_name" {
  description = "Secrets Manager name of the RDS credentials secret (petclinic/{env}/rds-credentials)."
  value       = aws_secretsmanager_secret.rds_credentials.name
}

output "master_username" {
  description = "Master username (password is only in Secrets Manager)."
  value       = aws_db_instance.this.username
}

output "db_subnet_group_name" {
  description = "DB subnet group name."
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "DB parameter group name."
  value       = aws_db_parameter_group.this.name
}
