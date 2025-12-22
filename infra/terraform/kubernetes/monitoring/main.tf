# =============================================================================
# Monitoring Infrastructure
# =============================================================================
# Prometheus, AlertManager, and Grafana for comprehensive monitoring.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# Create monitoring namespace if it doesn't exist
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace

    labels = {
      name       = var.namespace
      managed-by = "terraform"
    }
  }
}
