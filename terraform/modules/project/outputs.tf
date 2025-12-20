# =============================================================================
# Project Module Outputs
# =============================================================================

output "project_id" {
  description = "The project ID"
  value       = google_project.main.project_id
}

output "project_number" {
  description = "The project number"
  value       = google_project.main.number
}

output "project_name" {
  description = "The project name"
  value       = google_project.main.name
}

output "apis_ready" {
  description = "Dependency marker for when APIs are ready"
  value       = time_sleep.api_propagation.id
}
