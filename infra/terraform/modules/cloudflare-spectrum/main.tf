# =============================================================================
# Cloudflare Spectrum Module
# =============================================================================
# Proxies SSH traffic through Cloudflare with DDoS protection.
# Uses PROXY protocol to preserve real client IPs.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# SSH on standard port 22
# -----------------------------------------------------------------------------

resource "cloudflare_spectrum_application" "ssh" {
  zone_id      = var.zone_id
  protocol     = "ssh"
  traffic_type = "direct"

  dns {
    type = "CNAME"
    name = "ssh.${var.domain}"
  }

  origin_direct = ["tcp://${var.origin_ip}:22"]

  # Enable PROXY protocol to preserve client IPs
  proxy_protocol = "v1"

  # Smart routing for performance
  argo_smart_routing = var.enable_argo

  # IP firewall integration
  ip_firewall = true
}

# -----------------------------------------------------------------------------
# SSH on port 443 (bypass restrictive firewalls)
# -----------------------------------------------------------------------------

resource "cloudflare_spectrum_application" "ssh_443" {
  count = var.enable_ssh_443 ? 1 : 0

  zone_id      = var.zone_id
  protocol     = "tcp/443"
  traffic_type = "direct"

  dns {
    type = "CNAME"
    name = "git.${var.domain}"
  }

  origin_direct = ["tcp://${var.origin_ip}:22"]

  # Enable PROXY protocol to preserve client IPs
  proxy_protocol = "v1"

  # Smart routing for performance
  argo_smart_routing = var.enable_argo

  # IP firewall integration
  ip_firewall = true
}
