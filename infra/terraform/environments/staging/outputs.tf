# =============================================================================
# Staging Environment Outputs
# =============================================================================

output "project_id" {
  description = "GCP project ID"
  value       = module.project.project_id
}

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "database_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.cloudsql.instance_name
}

output "registry_url" {
  description = "Artifact Registry URL"
  value       = module.artifact_registry.repository_url
}

output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = module.kubernetes.load_balancer_ip
}

output "staging_url" {
  description = "Staging application URL"
  value       = "https://${var.subdomain}.${var.domain}"
}

output "sandbox_pool_enabled" {
  description = "Whether gVisor sandbox pool is enabled"
  value       = var.enable_sandbox_pool
}
