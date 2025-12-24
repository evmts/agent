# =============================================================================
# Resource Quotas and Limits
# =============================================================================
# Prevents resource exhaustion and controls costs by setting hard limits on
# resource consumption in the production namespace.
#
# Values chosen based on production workload requirements:
# - CPU requests: 20 cores (supports ~20-40 pods with moderate CPU needs)
# - Memory requests: 40Gi (supports ~20-40 pods with 1-2Gi each)
# - CPU limits: 40 cores (allows bursting for compute-intensive tasks)
# - Memory limits: 80Gi (prevents OOM while allowing headroom for spikes)
# - Pods: 100 (reasonable upper bound for main namespace)
# - Services: 20 (API, Web, monitoring, internal services)

# -----------------------------------------------------------------------------
# Resource Quota for plue namespace
# -----------------------------------------------------------------------------

resource "kubernetes_resource_quota" "plue" {
  metadata {
    name      = "plue-quota"
    namespace = "plue"

    labels = {
      app         = "plue"
      environment = "production"
      managed-by  = "terraform"
    }
  }

  spec {
    hard = {
      # CPU quotas - total for namespace
      "requests.cpu" = "20"
      "limits.cpu"   = "40"

      # Memory quotas - total for namespace
      "requests.memory" = "40Gi"
      "limits.memory"   = "80Gi"

      # Object count limits
      "pods"     = "100"
      "services" = "20"
    }
  }

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# LimitRange for plue namespace
# -----------------------------------------------------------------------------
# Sets default resource requests/limits for pods that don't specify them.
# Also enforces min/max bounds to prevent misconfiguration.

resource "kubernetes_limit_range" "plue" {
  metadata {
    name      = "plue-limits"
    namespace = "plue"

    labels = {
      app         = "plue"
      environment = "production"
      managed-by  = "terraform"
    }
  }

  spec {
    limit {
      type = "Container"

      # Default resources applied to containers without requests/limits
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      # Default requests applied to containers without requests
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }

      # Minimum resources a container can request
      min = {
        cpu    = "50m"
        memory = "64Mi"
      }

      # Maximum resources a container can request
      max = {
        cpu    = "4"
        memory = "8Gi"
      }
    }
  }

  depends_on = [module.kubernetes]
}
