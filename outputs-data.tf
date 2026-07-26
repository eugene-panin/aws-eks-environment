output "database_endpoint" {
  description = "Private PostgreSQL endpoint."
  value       = aws_db_instance.main.address
}

output "database_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.main.port
}

output "database_master_secret_arn" {
  description = "AWS Secrets Manager ARN containing the generated database administrator credentials."
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}

output "application_bucket_name" {
  description = "S3 bucket for application objects."
  value       = aws_s3_bucket.application.id
}
