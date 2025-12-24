# =============================================================================
# Cloudflare mTLS Module Variables
# =============================================================================

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "client_certificate" {
  description = "Client certificate PEM content (for Cloudflare to present to origin)"
  type        = string
  sensitive   = true
}

variable "client_private_key" {
  description = "Client private key PEM content"
  type        = string
  sensitive   = true
}

variable "rotation_days" {
  description = "Days between certificate rotations (should be less than cert validity)"
  type        = number
  default     = 90
}

variable "expiry_warning_days" {
  description = "Days before rotation to trigger warning"
  type        = number
  default     = 30
}
