# =============================================================================
# Secrets Module Outputs
# =============================================================================

output "workload_service_account_email" {
  description = "Email of the workload identity service account"
  value       = google_service_account.workload.email
}

output "workload_service_account_name" {
  description = "Name of the workload identity service account"
  value       = google_service_account.workload.name
}

output "anthropic_api_key_secret_id" {
  description = "Secret Manager secret ID for ANTHROPIC_API_KEY"
  value       = google_secret_manager_secret.anthropic_api_key.secret_id
}

output "session_secret_secret_id" {
  description = "Secret Manager secret ID for SESSION_SECRET"
  value       = google_secret_manager_secret.session_secret.secret_id
}
