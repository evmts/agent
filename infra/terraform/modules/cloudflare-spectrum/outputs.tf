# =============================================================================
# Cloudflare Spectrum Module Outputs
# =============================================================================

output "ssh_hostname" {
  description = "SSH hostname for git operations (port 22)"
  value       = "ssh.${var.domain}"
}

output "git_hostname" {
  description = "Git hostname for SSH over port 443"
  value       = var.enable_ssh_443 ? "git.${var.domain}" : null
}

output "spectrum_app_ids" {
  description = "Spectrum application IDs"
  value = {
    ssh     = cloudflare_spectrum_application.ssh.id
    ssh_443 = var.enable_ssh_443 ? cloudflare_spectrum_application.ssh_443[0].id : null
  }
}
