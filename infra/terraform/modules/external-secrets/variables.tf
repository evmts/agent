# =============================================================================
# External Secrets Operator Module Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install ESO into"
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account" {
  description = "Kubernetes service account name for ESO"
  type        = string
  default     = "external-secrets"
}

variable "labels" {
  description = "Labels to apply to GCP resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "plue"
  }
}
