# =============================================================================
# Cloudflare Workers Module
# =============================================================================
# Deploys the Plue edge worker with Durable Objects for Electric-synced SQLite.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# KV Namespace for caching (optional, for future use)
# -----------------------------------------------------------------------------

resource "cloudflare_workers_kv_namespace" "cache" {
  account_id = var.account_id
  title      = "plue-cache-${var.environment}"
}

# -----------------------------------------------------------------------------
# Workers Script with Durable Objects
# -----------------------------------------------------------------------------

resource "cloudflare_workers_script" "edge" {
  account_id = var.account_id
  name       = "plue-edge-${var.environment}"
  content    = file(var.worker_script_path)
  module     = true

  # Durable Object binding for data sync
  durable_object_binding {
    name       = "DATA_SYNC"
    class_name = "DataSyncDO"
  }

  # KV namespace binding
  kv_namespace_binding {
    name         = "CACHE"
    namespace_id = cloudflare_workers_kv_namespace.cache.id
  }

  # Environment variables
  plain_text_binding {
    name = "ORIGIN_HOST"
    text = var.origin_host
  }

  plain_text_binding {
    name = "ELECTRIC_URL"
    text = var.electric_url
  }

  # Secrets
  secret_text_binding {
    name = "JWT_SECRET"
    text = var.jwt_secret
  }

  secret_text_binding {
    name = "PUSH_SECRET"
    text = var.push_secret
  }
}

# -----------------------------------------------------------------------------
# Durable Object Migrations
# -----------------------------------------------------------------------------

# Note: Durable Object migrations are handled via wrangler.toml
# This resource ensures the DO namespace exists

resource "cloudflare_workers_script" "edge_do_migration" {
  count = 0 # Migrations handled by wrangler

  account_id = var.account_id
  name       = "plue-edge-${var.environment}"
  content    = file(var.worker_script_path)
  module     = true
}

# -----------------------------------------------------------------------------
# Custom Domain Routing
# -----------------------------------------------------------------------------

resource "cloudflare_worker_domain" "main" {
  account_id = var.account_id
  hostname   = var.domain
  service    = cloudflare_workers_script.edge.name
  zone_id    = var.zone_id
}

# Wildcard route for all paths
resource "cloudflare_worker_route" "main" {
  zone_id     = var.zone_id
  pattern     = "${var.domain}/*"
  script_name = cloudflare_workers_script.edge.name
}

# Root path route
resource "cloudflare_worker_route" "root" {
  zone_id     = var.zone_id
  pattern     = var.domain
  script_name = cloudflare_workers_script.edge.name
}
