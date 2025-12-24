# =============================================================================
# Cloudflare mTLS (Authenticated Origin Pulls) Module
# =============================================================================
# Configures Cloudflare to present a client certificate when connecting
# to the origin server. The origin server should be configured to require
# this certificate, effectively blocking all non-Cloudflare traffic.
#
# Using a custom certificate (not Cloudflare's shared cert) prevents
# other Cloudflare users from pointing their domains at our origin.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# -----------------------------------------------------------------------------
# Certificate Rotation Tracking
# -----------------------------------------------------------------------------
# Tracks certificate expiry and triggers rotation warnings.
# Certificates should be rotated every 90 days (before 365-day expiry).

resource "time_rotating" "cert_rotation" {
  rotation_days = var.rotation_days
}

resource "time_static" "cert_created" {
  triggers = {
    rotation = time_rotating.cert_rotation.id
  }
}

locals {
  # Calculate days until next rotation
  rotation_timestamp = time_rotating.cert_rotation.rotation_rfc3339
}

# -----------------------------------------------------------------------------
# Upload Custom Client Certificate
# -----------------------------------------------------------------------------

resource "cloudflare_authenticated_origin_pulls_certificate" "origin" {
  zone_id     = var.zone_id
  certificate = var.client_certificate
  private_key = var.client_private_key
  type        = "per-zone"
}

# -----------------------------------------------------------------------------
# Enable Authenticated Origin Pulls
# -----------------------------------------------------------------------------

resource "cloudflare_authenticated_origin_pulls" "origin" {
  zone_id                                = var.zone_id
  authenticated_origin_pulls_certificate = cloudflare_authenticated_origin_pulls_certificate.origin.id
  enabled                                = true
}
