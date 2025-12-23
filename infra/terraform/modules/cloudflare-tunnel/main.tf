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
        # SECURITY NOTE: TLS verification disabled for internal cluster services
        # Justification: These are ClusterIP services within the private GKE cluster
        # that do not have TLS configured. The traffic flow is:
        # 1. External traffic arrives via Cloudflare (TLS terminated at edge)
        # 2. Cloudflare Tunnel (running in-cluster) connects to ClusterIP services
        # 3. All traffic stays within the private cluster network
        # Risk mitigation: GKE network policies and private cluster configuration
        # prevent external access to these services outside the tunnel.
        no_tls_verify = true
      }
    }

    # API service (Hono)
    ingress_rule {
      hostname = "api.internal"
      service  = var.origin_api_service

      origin_request {
        # SECURITY NOTE: TLS verification disabled (see web service above for details)
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
