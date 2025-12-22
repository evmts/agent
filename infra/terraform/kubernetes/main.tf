# =============================================================================
# Kubernetes Resources
# =============================================================================
# Configures Kubernetes provider and deploys application resources.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "plue" {
  metadata {
    name = var.namespace

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Service Account with Workload Identity
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "workload" {
  metadata {
    name      = "plue-workload"
    namespace = kubernetes_namespace.plue.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = var.workload_sa_email
    }

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }
}
