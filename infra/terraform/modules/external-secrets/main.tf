# =============================================================================
# External Secrets Operator Module
# =============================================================================
# Deploys External Secrets Operator (ESO) to sync secrets from GCP Secret
# Manager into Kubernetes, replacing manual secret management and eliminating
# secrets from Terraform state.
#
# How ESO works:
# 1. ESO watches ExternalSecret custom resources in the cluster
# 2. When it finds one, it fetches the secret from GCP Secret Manager
# 3. ESO creates/updates a native Kubernetes Secret with the data
# 4. Pods mount the K8s Secret like normal (no code changes needed)
# 5. ESO refreshes secrets automatically (default: 1 hour)
#
# Architecture:
# - Uses Workload Identity (no service account keys stored anywhere)
# - ClusterSecretStore provides GCP Secret Manager access cluster-wide
# - ExternalSecret resources define which secrets to sync
# - Secrets are encrypted at rest in etcd by GKE

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# -----------------------------------------------------------------------------
# External Secrets Operator Helm Chart
# -----------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.11"  # Pin to stable version
  namespace  = var.namespace

  create_namespace = true

  values = [
    yamlencode({
      # Install CRDs with the chart
      installCRDs = true

      # Security context for pods
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534  # nobody
        fsGroup      = 65534
      }

      # Pod-level security context
      podSecurityContext = {
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Resource limits to prevent resource exhaustion
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }

      # High availability for production
      replicaCount = 2

      # Pod disruption budget
      podDisruptionBudget = {
        enabled        = true
        minAvailable   = 1
      }

      # Prometheus metrics
      metrics = {
        enabled = true
        service = {
          enabled = true
          port    = 8080
        }
      }

      # Service account annotations for Workload Identity
      serviceAccount = {
        create = true
        name   = var.eso_service_account
        annotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.eso.email
        }
      }
    })
  ]

  depends_on = [google_service_account_iam_member.eso_workload_identity]
}
