# =============================================================================
# Cloudflare Workers Module Outputs
# =============================================================================

output "worker_name" {
  description = "Name of the deployed worker"
  value       = cloudflare_workers_script.edge.name
}

output "worker_url" {
  description = "URL of the worker"
  value       = "https://${var.domain}"
}

output "kv_namespace_id" {
  description = "ID of the KV namespace"
  value       = cloudflare_workers_kv_namespace.cache.id
}
