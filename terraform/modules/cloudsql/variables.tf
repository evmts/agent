# =============================================================================
# Cloud SQL Module Variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "vpc_id" {
  description = "VPC network ID for private IP"
  type        = string
}

variable "private_vpc_connection" {
  description = "Private service connection dependency"
  type        = string
}

variable "tier" {
  description = "Cloud SQL instance tier (machine type)"
  type        = string
  default     = "db-custom-2-8192" # 2 vCPU, 8GB RAM
}

variable "disk_size_gb" {
  description = "Initial disk size in GB"
  type        = number
  default     = 50
}

variable "ha_enabled" {
  description = "Enable regional high availability"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of backups to retain"
  type        = number
  default     = 14
}

variable "deletion_protection" {
  description = "Prevent accidental deletion"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "plue"
  }
}
