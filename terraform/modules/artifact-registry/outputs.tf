# =============================================================================
# Artifact Registry Module Outputs
# =============================================================================

output "repository_id" {
  description = "The repository ID"
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_name" {
  description = "The full repository name"
  value       = google_artifact_registry_repository.docker.name
}

output "repository_url" {
  description = "The Docker repository URL for pushing/pulling images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
