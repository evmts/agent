# =============================================================================
# Cloudflare Tunnel Module Variables
# =============================================================================

variable "account_id" {
  type        = string
  description = "Cloudflare account ID"
}

variable "tunnel_name" {
  type        = string
  description = "Name for the Cloudflare tunnel"
  default     = "plue-origin-tunnel"
}

variable "tunnel_secret" {
  type        = string
  sensitive   = true
  description = "Secret for the tunnel (32+ bytes, base64 encoded)"
}

variable "origin_web_service" {
  type        = string
  description = "Internal URL for the web service"
  default     = "http://web:5173"
}

variable "origin_api_service" {
  type        = string
  description = "Internal URL for the API service"
  default     = "http://api:4000"
}

variable "origin_electric_service" {
  type        = string
  description = "Internal URL for the ElectricSQL service"
  default     = "http://electric:3000"
}
