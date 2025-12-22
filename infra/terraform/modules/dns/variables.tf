# =============================================================================
# Cloudflare DNS Module Variables
# =============================================================================

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}

variable "domain" {
  description = "Base domain name (e.g., example.com)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the application (e.g., 'plue' for plue.example.com). Empty for root domain."
  type        = string
  default     = ""
}

variable "load_balancer_ip" {
  description = "IP address of the GKE LoadBalancer"
  type        = string
}

variable "enable_proxy" {
  description = "Enable Cloudflare proxy (orange cloud) for CDN and DDoS protection"
  type        = bool
  default     = true
}

variable "enable_adminer_dns" {
  description = "Create DNS record for Adminer (database admin)"
  type        = bool
  default     = true
}

variable "enable_page_rules" {
  description = "Create Cloudflare page rules for caching"
  type        = bool
  default     = false
}
