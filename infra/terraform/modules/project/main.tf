# =============================================================================
# GCP Project Bootstrap
# =============================================================================
# Creates GCP project and enables required APIs for the Plue application.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Project
# -----------------------------------------------------------------------------

resource "google_project" "main" {
  name            = var.project_name
  project_id      = var.project_id
  org_id          = var.org_id
  billing_account = var.billing_account

  labels = var.labels
}

# -----------------------------------------------------------------------------
# Enable Required APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "apis" {
  for_each = toset([
    # Core Infrastructure
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",

    # Database
    "sqladmin.googleapis.com",

    # Security & IAM
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",

    # Container Registry
    "artifactregistry.googleapis.com",

    # Observability
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",

    # Cloud Build (for CI/CD)
    "cloudbuild.googleapis.com",
  ])

  project                    = google_project.main.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# -----------------------------------------------------------------------------
# Wait for API propagation
# -----------------------------------------------------------------------------

resource "time_sleep" "api_propagation" {
  depends_on = [google_project_service.apis]

  create_duration = "60s"
}
