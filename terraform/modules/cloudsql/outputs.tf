# =============================================================================
# Cloud SQL Module Outputs
# =============================================================================

output "instance_name" {
  description = "The Cloud SQL instance name"
  value       = google_sql_database_instance.postgres.name
}

output "instance_connection_name" {
  description = "The connection name for Cloud SQL Proxy"
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip" {
  description = "The private IP address of the instance"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  description = "The database name"
  value       = google_sql_database.electric.name
}

output "database_user" {
  description = "The database username"
  value       = google_sql_user.postgres.name
}

output "database_url_secret_id" {
  description = "Secret Manager secret ID for DATABASE_URL"
  value       = google_secret_manager_secret.database_url.secret_id
}

output "database_url_secret_name" {
  description = "Secret Manager secret name for DATABASE_URL"
  value       = google_secret_manager_secret.database_url.name
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID for database password"
  value       = google_secret_manager_secret.db_password.secret_id
}
