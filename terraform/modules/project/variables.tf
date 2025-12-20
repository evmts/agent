# =============================================================================
# Project Module Variables
# =============================================================================

variable "project_name" {
  description = "Human-readable project name"
  type        = string
}

variable "project_id" {
  description = "Unique GCP project ID (must be globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "org_id" {
  description = "GCP Organization ID"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to associate with the project"
  type        = string
}

variable "labels" {
  description = "Labels to apply to the project"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "plue"
  }
}
