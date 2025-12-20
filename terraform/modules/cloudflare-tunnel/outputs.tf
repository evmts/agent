# =============================================================================
# Cloudflare Tunnel Module Outputs
# =============================================================================

output "tunnel_id" {
  description = "ID of the Cloudflare tunnel"
  value       = cloudflare_tunnel.origin.id
}

output "tunnel_name" {
  description = "Name of the Cloudflare tunnel"
  value       = cloudflare_tunnel.origin.name
}

output "tunnel_token" {
  description = "Token for cloudflared to connect (base64 encoded credentials)"
  value       = base64encode(local.tunnel_credentials)
  sensitive   = true
}

output "tunnel_cname" {
  description = "CNAME target for the tunnel"
  value       = cloudflare_tunnel.origin.cname
}
