# =============================================================================
# Secrets Module Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "database_url_secret_id" {
  description = "Secret Manager secret ID for DATABASE_URL (from cloudsql module)"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for workload identity binding"
  type        = string
  default     = "plue"
}

variable "k8s_service_account" {
  description = "Kubernetes service account name for workload identity binding"
  type        = string
  default     = "plue-workload"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "plue"
  }
}
