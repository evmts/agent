# =============================================================================
# Cloudflare Workers Module Variables
# =============================================================================

variable "account_id" {
  type        = string
  description = "Cloudflare account ID"
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID for the domain"
}

variable "domain" {
  type        = string
  description = "Domain name for the workers (e.g., plue.dev)"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., production, staging)"
  default     = "production"
}

variable "worker_script_path" {
  type        = string
  description = "Path to the built worker script"
  default     = "../../../edge/dist/index.js"
}

variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "Secret for JWT token signing/verification"
}

variable "origin_host" {
  type        = string
  description = "Internal hostname for origin server (via tunnel)"
  default     = "origin.internal"
}

variable "electric_url" {
  type        = string
  description = "ElectricSQL endpoint URL (via tunnel)"
  default     = "http://electric.internal:3000"
}

variable "push_secret" {
  description = "Shared secret for K8s to authenticate push invalidations to Workers"
  type        = string
  sensitive   = true
}
