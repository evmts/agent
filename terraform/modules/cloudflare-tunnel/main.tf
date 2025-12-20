# =============================================================================
# Cloudflare Tunnel Module
# =============================================================================
# Creates a Cloudflare Tunnel to securely connect Workers to private GKE.
# The tunnel runs as a cloudflared daemon inside the GKE cluster.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Cloudflare Tunnel
# -----------------------------------------------------------------------------

resource "cloudflare_tunnel" "origin" {
  account_id = var.account_id
  name       = var.tunnel_name
  secret     = var.tunnel_secret
}

# -----------------------------------------------------------------------------
# Tunnel Configuration (Ingress Rules)
# -----------------------------------------------------------------------------

resource "cloudflare_tunnel_config" "origin" {
  account_id = var.account_id
  tunnel_id  = cloudflare_tunnel.origin.id

  config {
    # Web service (Astro SSR for git pages)
    ingress_rule {
      hostname = "origin.internal"
      service  = var.origin_web_service

      origin_request {
        no_tls_verify = true
      }
    }

    # API service (Hono)
    ingress_rule {
      hostname = "api.internal"
      service  = var.origin_api_service

      origin_request {
        no_tls_verify = true
      }
    }

    # ElectricSQL service
    ingress_rule {
      hostname = "electric.internal"
      service  = var.origin_electric_service

      origin_request {
        no_tls_verify = true
      }
    }

    # Catch-all (required)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# -----------------------------------------------------------------------------
# Output the tunnel token for GKE deployment
# -----------------------------------------------------------------------------
# The tunnel token is used by cloudflared running in GKE to authenticate

locals {
  # Generate the tunnel token (account_id:tunnel_id:secret)
  tunnel_credentials = jsonencode({
    AccountTag   = var.account_id
    TunnelID     = cloudflare_tunnel.origin.id
    TunnelName   = cloudflare_tunnel.origin.name
    TunnelSecret = var.tunnel_secret
  })
}
