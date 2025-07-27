output "instance_id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.main.id
}

output "instance_address" {
  description = "Address of the RDS instance"
  value       = aws_db_instance.main.address
}

output "instance_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "instance_port" {
  description = "Port of the RDS instance"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "database_username" {
  description = "Master username for the database"
  value       = aws_db_instance.main.username
}

output "security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "password_secret_arn" {
  description = "ARN of the secret containing the database password"
  value       = aws_secretsmanager_secret.database_password.arn
}

output "connection_secret_arn" {
  description = "ARN of the secret containing the database connection details"
  value       = aws_secretsmanager_secret.database_connection.arn
}

output "subnet_group_name" {
  description = "Name of the database subnet group"
  value       = aws_db_subnet_group.main.name
}