# =============================================================================
# Cloudflare Spectrum Module Variables
# =============================================================================

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "domain" {
  description = "Base domain (e.g., plue.dev)"
  type        = string
}

variable "origin_ip" {
  description = "Origin server IP or hostname for SSH"
  type        = string
}

variable "enable_argo" {
  description = "Enable Argo Smart Routing for improved performance"
  type        = bool
  default     = true
}

variable "enable_ssh_443" {
  description = "Enable SSH on port 443 for bypassing restrictive firewalls"
  type        = bool
  default     = true
}
