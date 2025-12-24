# =============================================================================
# Cloudflare mTLS Module Outputs
# =============================================================================

output "certificate_id" {
  description = "ID of the uploaded client certificate"
  value       = cloudflare_authenticated_origin_pulls_certificate.origin.id
}

output "enabled" {
  description = "Whether Authenticated Origin Pulls is enabled"
  value       = cloudflare_authenticated_origin_pulls.origin.enabled
}

output "next_rotation" {
  description = "When certificates should be rotated (RFC3339 timestamp)"
  value       = time_rotating.cert_rotation.rotation_rfc3339
}

output "cert_created_at" {
  description = "When current certificate rotation period started"
  value       = time_static.cert_created.rfc3339
}

output "status" {
  description = "mTLS configuration status summary"
  value = {
    enabled       = cloudflare_authenticated_origin_pulls.origin.enabled
    cert_id       = cloudflare_authenticated_origin_pulls_certificate.origin.id
    next_rotation = time_rotating.cert_rotation.rotation_rfc3339
    created_at    = time_static.cert_created.rfc3339
  }
}
