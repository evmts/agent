# =============================================================================
# Pod Disruption Budgets
# =============================================================================
# Ensures high availability during voluntary disruptions (node upgrades, drains).
# Without PDBs, all pods could be terminated simultaneously during maintenance.
#
# minAvailable policy:
# - API: 1 replica must stay running (ensures request handling during updates)
# - Web: 1 replica must stay running (ensures frontend availability)
# - Runner standby: 2 replicas must stay running (maintains warm pool for <500ms cold starts)
#
# These values balance availability with update speed - higher values increase
# resilience but slow down cluster maintenance operations.

# API Service PDB
# Protects the Zig API server during node maintenance
resource "kubernetes_pod_disruption_budget_v1" "api" {
  metadata {
    name      = "api-pdb"
    namespace = var.namespace

    labels = {
      app        = "api"
      managed-by = "terraform"
    }
  }

  spec {
    min_available = "1"

    selector {
      match_labels = {
        app = "api"
      }
    }
  }
}

# Web Service PDB
# Protects the Astro SSR frontend during node maintenance
# Note: Web uses a single replica with RWO PVC (see web.tf line 41)
# Using maxUnavailable: 0 ensures the pod is not disrupted, preventing downtime
# during voluntary disruptions. K8s will wait for manual intervention if the
# node needs to be drained.
resource "kubernetes_pod_disruption_budget_v1" "web" {
  metadata {
    name      = "web-pdb"
    namespace = var.namespace

    labels = {
      app        = "web"
      managed-by = "terraform"
    }
  }

  spec {
    max_unavailable = "0"

    selector {
      match_labels = {
        app = "web"
      }
    }
  }
}

# Note: Runner Standby Pool PDB is defined in infra/k8s/pod-disruption-budgets.yaml
# because the runner warm pool is managed via YAML manifests (not Terraform).
