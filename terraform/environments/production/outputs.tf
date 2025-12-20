# =============================================================================
# Production Environment Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# GCP
# -----------------------------------------------------------------------------

output "project_id" {
  description = "GCP Project ID"
  value       = module.project.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

# -----------------------------------------------------------------------------
# GKE
# -----------------------------------------------------------------------------

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_get_credentials_command" {
  description = "Command to get GKE credentials"
  value       = module.gke.get_credentials_command
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.cloudsql.instance_name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name (for Cloud SQL Proxy)"
  value       = module.cloudsql.instance_connection_name
}

# -----------------------------------------------------------------------------
# Container Registry
# -----------------------------------------------------------------------------

output "registry_url" {
  description = "Artifact Registry URL"
  value       = module.artifact_registry.repository_url
}

output "docker_push_commands" {
  description = "Commands to build and push Docker images"
  value       = <<-EOT
    # Authenticate Docker with Artifact Registry
    gcloud auth configure-docker ${var.region}-docker.pkg.dev

    # Build and push API image
    docker build --target api -t ${module.artifact_registry.repository_url}/plue-api:${var.image_tag} .
    docker push ${module.artifact_registry.repository_url}/plue-api:${var.image_tag}

    # Build and push Web image
    docker build --target web -t ${module.artifact_registry.repository_url}/plue-web:${var.image_tag} .
    docker push ${module.artifact_registry.repository_url}/plue-web:${var.image_tag}
  EOT
}

# -----------------------------------------------------------------------------
# URLs
# -----------------------------------------------------------------------------

output "web_url" {
  description = "Web application URL"
  value       = module.dns.web_url
}

output "api_url" {
  description = "API URL"
  value       = module.dns.api_url
}

output "load_balancer_ip" {
  description = "LoadBalancer IP address"
  value       = module.kubernetes.load_balancer_ip
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

output "anthropic_api_key_secret" {
  description = "Secret Manager secret for ANTHROPIC_API_KEY (add value manually)"
  value       = module.secrets.anthropic_api_key_secret_id
}

output "add_anthropic_key_command" {
  description = "Command to add ANTHROPIC_API_KEY"
  value       = "echo -n 'YOUR_KEY' | gcloud secrets versions add ${module.secrets.anthropic_api_key_secret_id} --data-file=-"
}
