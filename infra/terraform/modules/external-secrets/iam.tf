# =============================================================================
# External Secrets Operator IAM Configuration
# =============================================================================
# Sets up Workload Identity for ESO to access GCP Secret Manager.
#
# How Workload Identity works:
# 1. GKE pod runs with K8s service account (eso-sa)
# 2. K8s SA is annotated with GCP SA email
# 3. GKE binds K8s SA to GCP SA via IAM policy
# 4. Pod authenticates to GCP APIs using K8s SA token
# 5. GCP verifies and allows access based on GCP SA permissions
#
# This eliminates the need for service account keys, which:
# - Cannot be rotated automatically
# - Must be stored as Kubernetes secrets
# - Create security risks if leaked

# -----------------------------------------------------------------------------
# GCP Service Account for ESO
# -----------------------------------------------------------------------------

resource "google_service_account" "eso" {
  account_id   = "${var.name_prefix}-eso"
  display_name = "External Secrets Operator"
  description  = "Service account for External Secrets Operator to access Secret Manager"
  project      = var.project_id
}

# -----------------------------------------------------------------------------
# Grant Secret Manager Access
# -----------------------------------------------------------------------------
# ESO needs roles/secretmanager.secretAccessor to read secret values.
# This is granted at the project level so ESO can access all secrets.
#
# For finer-grained control, grant per-secret IAM instead:
#   resource "google_secret_manager_secret_iam_member" "eso_example" {
#     secret_id = "secret-name"
#     role      = "roles/secretmanager.secretAccessor"
#     member    = "serviceAccount:${google_service_account.eso.email}"
#   }

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# Optional: Grant viewer role to list secrets (useful for debugging)
resource "google_project_iam_member" "eso_secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Binding
# -----------------------------------------------------------------------------
# Binds the K8s service account to the GCP service account.
# Format: serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.eso_service_account}]"
}
