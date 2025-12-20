# =============================================================================
# Kubernetes Module Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Plue resources"
  type        = string
  default     = "plue"
}

variable "workload_sa_email" {
  description = "GCP service account email for workload identity"
  type        = string
}

variable "database_url_secret_name" {
  description = "Secret Manager secret name for DATABASE_URL"
  type        = string
}

variable "anthropic_api_key_secret_id" {
  description = "Secret Manager secret ID for ANTHROPIC_API_KEY"
  type        = string
}

variable "session_secret_secret_id" {
  description = "Secret Manager secret ID for SESSION_SECRET"
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

# Service-specific variables
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

variable "service_account_name" {
  description = "Kubernetes service account name for workload identity"
  type        = string
  default     = "plue-workload"
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare tunnel token for cloudflared daemon"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_cloudflare_tunnel" {
  description = "Whether to deploy cloudflared tunnel daemon"
  type        = bool
  default     = false
}

variable "enable_external_lb" {
  description = "Whether to create an external LoadBalancer (disable when using Cloudflare Tunnel)"
  type        = bool
  default     = true
}
