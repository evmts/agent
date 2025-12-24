# =============================================================================
# Cloudflare Workers Module
# =============================================================================
# Deploys the Plue edge worker for caching and routing.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# KV Namespaces
# -----------------------------------------------------------------------------

resource "cloudflare_workers_kv_namespace" "cache" {
  account_id = var.account_id
  title      = "plue-cache-${var.environment}"
}

# Note: Auth has been migrated from KV to Durable Objects for strong consistency
# The old plue-auth-* KV namespace can be deleted after migration is verified

# -----------------------------------------------------------------------------
# Workers Script with Durable Objects
# -----------------------------------------------------------------------------

resource "cloudflare_workers_script" "edge" {
  account_id = var.account_id
  name       = "plue-edge-${var.environment}"
  content    = file(var.worker_script_path)
  module     = true

  # Durable Object binding for authentication state (nonces, sessions, blocklist)
  # Uses DO instead of KV for strong consistency on nonce replay protection
  durable_object_binding {
    name       = "AUTH_DO"
    class_name = "AuthDO"
  }

  # Durable Object binding for rate limiting
  # Uses DO for atomic counters with strong consistency
  durable_object_binding {
    name       = "RATE_LIMIT_DO"
    class_name = "RateLimitDO"
  }

  # Durable Object binding for metrics aggregation
  # Collects metrics across all edge instances for Prometheus scraping
  durable_object_binding {
    name       = "METRICS_DO"
    class_name = "MetricsDO"
  }

  # Analytics Engine binding (optional, for detailed analytics)
  # Uncomment when Analytics Engine is enabled on the account
  # analytics_engine_binding {
  #   name    = "ANALYTICS"
  #   dataset = "plue_edge_analytics"
  # }

  # KV namespace bindings
  kv_namespace_binding {
    name         = "CACHE"
    namespace_id = cloudflare_workers_kv_namespace.cache.id
  }

  # Environment variables
  plain_text_binding {
    name = "ORIGIN_HOST"
    text = var.origin_host
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
