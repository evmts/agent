# =============================================================================
# External Secrets Operator Module Outputs
# =============================================================================

output "eso_service_account_email" {
  description = "Email of the GCP service account used by ESO"
  value       = google_service_account.eso.email
}

output "eso_service_account_name" {
  description = "Name of the GCP service account used by ESO"
  value       = google_service_account.eso.name
}

output "namespace" {
  description = "Kubernetes namespace where ESO is installed"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Name of the ESO Helm release"
  value       = helm_release.external_secrets.name
}

output "helm_release_status" {
  description = "Status of the ESO Helm release"
  value       = helm_release.external_secrets.status
}
