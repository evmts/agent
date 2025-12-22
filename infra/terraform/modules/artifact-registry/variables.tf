# =============================================================================
# Artifact Registry Module Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (used as repository ID)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (for Cloud Build SA)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "gke_node_sa_email" {
  description = "GKE node service account email for read access"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "plue"
  }
}
