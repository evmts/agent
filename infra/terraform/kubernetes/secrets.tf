# =============================================================================
# Kubernetes Secrets
# =============================================================================
# Creates K8s secrets from GCP Secret Manager.
#
# Note: In production, consider using External Secrets Operator for better
# secret rotation. This approach uses the secrets-store-csi-driver as an
# alternative.

# For simplicity, we use Terraform to sync secrets.
# The secrets are fetched from GCP Secret Manager and created as K8s secrets.

data "google_secret_manager_secret_version" "database_url" {
  secret  = var.database_url_secret_name
  project = var.project_id
}

data "google_secret_manager_secret_version" "anthropic_api_key" {
  secret  = var.anthropic_api_key_secret_id
  project = var.project_id
}

data "google_secret_manager_secret_version" "session_secret" {
  secret  = var.session_secret_secret_id
  project = var.project_id
}

resource "kubernetes_secret" "database_url" {
  metadata {
    name      = "database-url"
    namespace = kubernetes_namespace.plue.metadata[0].name

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  data = {
    url = data.google_secret_manager_secret_version.database_url.secret_data
  }

  type = "Opaque"
}

resource "kubernetes_secret" "anthropic_api_key" {
  metadata {
    name      = "anthropic-api-key"
    namespace = kubernetes_namespace.plue.metadata[0].name

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  data = {
    key = data.google_secret_manager_secret_version.anthropic_api_key.secret_data
  }

  type = "Opaque"
}

resource "kubernetes_secret" "session_secret" {
  metadata {
    name      = "session-secret"
    namespace = kubernetes_namespace.plue.metadata[0].name

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  data = {
    secret = data.google_secret_manager_secret_version.session_secret.secret_data
  }

  type = "Opaque"
}

resource "kubernetes_secret" "edge_push_secret" {
  metadata {
    name      = "edge-push-secret"
    namespace = kubernetes_namespace.plue.metadata[0].name

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  data = {
    secret = var.edge_push_secret
  }

  type = "Opaque"
}
