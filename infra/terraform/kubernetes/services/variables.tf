# =============================================================================
# Kubernetes Services Variables
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
}

variable "registry_url" {
  description = "Container registry URL"
  type        = string
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "domain" {
  description = "Domain for the application"
  type        = string
}

variable "database_host" {
  description = "Database host for Adminer"
  type        = string
}

variable "schema_file_path" {
  description = "Path to schema.sql file"
  type        = string
}

variable "schema_hash" {
  description = "Hash of schema.sql for job naming"
  type        = string
}

# Service-specific
variable "api_replicas" {
  description = "Number of API replicas"
  type        = number
  default     = 2
}

variable "electric_storage_size" {
  description = "Storage size for ElectricSQL"
  type        = string
  default     = "50Gi"
}

variable "repos_storage_size" {
  description = "Storage size for git repos"
  type        = string
  default     = "100Gi"
}
