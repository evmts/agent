# =============================================================================
# Cloudflare DNS Module Outputs
# =============================================================================

output "web_hostname" {
  description = "Hostname for the web application"
  value       = local.web_hostname
}

output "api_hostname" {
  description = "Hostname for the API service"
  value       = local.api_hostname
}

output "adminer_hostname" {
  description = "Hostname for Adminer"
  value       = var.enable_adminer_dns ? (var.subdomain != "" ? "adminer.${var.subdomain}.${var.domain}" : "adminer.${var.domain}") : null
}

output "web_url" {
  description = "Full URL for the web application"
  value       = "https://${local.web_hostname}"
}

output "api_url" {
  description = "Full URL for the API service"
  value       = "https://${local.api_hostname}"
}
