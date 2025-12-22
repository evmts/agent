# =============================================================================
# GKE Module Outputs
# =============================================================================

output "cluster_id" {
  description = "The cluster ID"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "The cluster location (region)"
  value       = google_container_cluster.primary.location
}

output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_nodes.email
}

output "workload_identity_pool" {
  description = "Workload identity pool for the cluster"
  value       = "${var.project_id}.svc.id.goog"
}

# Connection command helper
output "get_credentials_command" {
  description = "gcloud command to get cluster credentials"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

# Sandbox pool outputs
output "sandbox_pool_enabled" {
  description = "Whether the sandbox node pool is enabled"
  value       = var.enable_sandbox_pool
}

output "sandbox_pool_name" {
  description = "Name of the sandbox node pool"
  value       = var.enable_sandbox_pool ? google_container_node_pool.sandbox[0].name : null
}
