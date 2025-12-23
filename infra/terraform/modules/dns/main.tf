# =============================================================================
# Cloudflare DNS Module
# =============================================================================
# Creates DNS records pointing to GKE LoadBalancer.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# DNS Records
# -----------------------------------------------------------------------------

# Main web app record
resource "cloudflare_record" "web" {
  zone_id = var.cloudflare_zone_id
  name    = var.subdomain != "" ? var.subdomain : "@"
  content = var.load_balancer_ip
  type    = "A"
  proxied = var.enable_proxy
  ttl     = var.enable_proxy ? 1 : 300 # Auto when proxied

  comment = "Plue web application"
}

# API subdomain
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.subdomain != "" ? "api.${var.subdomain}" : "api"
  content = var.load_balancer_ip
  type    = "A"
  proxied = var.enable_proxy
  ttl     = var.enable_proxy ? 1 : 300

  comment = "Plue API service"
}

# Adminer (database admin) - optional
resource "cloudflare_record" "adminer" {
  count = var.enable_adminer_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.subdomain != "" ? "adminer.${var.subdomain}" : "adminer"
  content = var.load_balancer_ip
  type    = "A"
  proxied = var.enable_proxy
  ttl     = var.enable_proxy ? 1 : 300

  comment = "Plue database admin (Adminer)"
}

# -----------------------------------------------------------------------------
# Cloudflare Page Rules (Optional)
# -----------------------------------------------------------------------------

# Cache static assets aggressively
resource "cloudflare_page_rule" "cache_static" {
  count = var.enable_page_rules ? 1 : 0

  zone_id  = var.cloudflare_zone_id
  target   = "${local.web_hostname}/_astro/*"
  priority = 1

  actions {
    cache_level = "cache_everything"
    edge_cache_ttl = 86400 # 1 day
  }
}

# Bypass cache for API
resource "cloudflare_page_rule" "api_bypass" {
  count = var.enable_page_rules ? 1 : 0

  zone_id  = var.cloudflare_zone_id
  target   = "${local.api_hostname}/*"
  priority = 2

  actions {
    cache_level = "bypass"
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  base_domain  = var.domain
  web_hostname = var.subdomain != "" ? "${var.subdomain}.${var.domain}" : var.domain
  api_hostname = var.subdomain != "" ? "api.${var.subdomain}.${var.domain}" : "api.${var.domain}"
}
