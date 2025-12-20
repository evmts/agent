# =============================================================================
# Secrets Module
# =============================================================================
# Creates Secret Manager secrets and Workload Identity for GKE access.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Application Secrets
# -----------------------------------------------------------------------------

# Anthropic API Key (placeholder - user adds value manually)
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "${var.name_prefix}-anthropic-api-key"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

# Session Secret (auto-generated)
resource "random_password" "session_secret" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret" "session_secret" {
  secret_id = "${var.name_prefix}-session-secret"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "session_secret" {
  secret      = google_secret_manager_secret.session_secret.id
  secret_data = random_password.session_secret.result
}

# -----------------------------------------------------------------------------
# Workload Identity Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "workload" {
  account_id   = "${var.name_prefix}-workload"
  display_name = "Plue Workload Identity"
  description  = "Service account for Plue GKE workloads"
  project      = var.project_id
}

# Grant Secret Manager access
resource "google_secret_manager_secret_iam_member" "workload_anthropic" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload.email}"
}

resource "google_secret_manager_secret_iam_member" "workload_session" {
  secret_id = google_secret_manager_secret.session_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload.email}"
}

resource "google_secret_manager_secret_iam_member" "workload_database_url" {
  secret_id = var.database_url_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload.email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Binding
# -----------------------------------------------------------------------------

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
}

# -----------------------------------------------------------------------------
# Cloud SQL Client Role (for potential direct access)
# -----------------------------------------------------------------------------

resource "google_project_iam_member" "workload_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.workload.email}"
}
