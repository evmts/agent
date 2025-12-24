# =============================================================================
# Production Environment Variables
# =============================================================================

# -----------------------------------------------------------------------------
# GCP Project
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Human-readable project name"
  type        = string
  default     = "Plue Production"
}

variable "project_id" {
  description = "Unique GCP project ID"
  type        = string
}

variable "org_id" {
  description = "GCP Organization ID"
  type        = string
}

variable "billing_account" {
  description = "GCP Billing Account ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-west1"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "gke_subnet_cidr" {
  description = "CIDR for GKE nodes"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR for GKE pods"
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "CIDR for GKE services"
  type        = string
  default     = "10.8.0.0/20"
}

# -----------------------------------------------------------------------------
# GKE
# -----------------------------------------------------------------------------

variable "gke_node_zones" {
  description = "Zones for GKE nodes"
  type        = list(string)
  default     = ["us-west1-a", "us-west1-b", "us-west1-c"]
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "gke_min_nodes" {
  description = "Minimum nodes per zone"
  type        = number
  default     = 1
}

variable "gke_max_nodes" {
  description = "Maximum nodes per zone"
  type        = number
  default     = 5
}

# -----------------------------------------------------------------------------
# GKE Sandbox Pool (for workflow runners)
# -----------------------------------------------------------------------------

variable "enable_sandbox_pool" {
  description = "Enable gVisor sandbox node pool for workflow runners"
  type        = bool
  default     = false  # Opt-in for production
}

variable "sandbox_machine_type" {
  description = "Machine type for sandbox nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "sandbox_pool_min_size" {
  description = "Minimum sandbox pool nodes"
  type        = number
  default     = 1
}

variable "sandbox_pool_max_size" {
  description = "Maximum sandbox pool nodes"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# Cloud SQL
# -----------------------------------------------------------------------------

variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-8192"
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 50
}

variable "db_ha_enabled" {
  description = "Enable Cloud SQL regional HA"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Domain & DNS
# -----------------------------------------------------------------------------

variable "domain" {
  description = "Domain name for the application"
  type        = string
}

variable "subdomain" {
  description = "Subdomain (empty for root domain)"
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID (required for Workers and Tunnels)"
  type        = string
  default     = ""
}

variable "enable_edge" {
  description = "Enable Cloudflare Workers edge deployment"
  type        = bool
  default     = false
}

variable "edge_push_secret" {
  description = "Shared secret for K8s to authenticate push invalidations to Workers"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_spectrum" {
  description = "Enable Cloudflare Spectrum for SSH traffic"
  type        = bool
  default     = true
}

variable "enable_mtls" {
  description = "Enable mTLS (Authenticated Origin Pulls) for origin protection"
  type        = bool
  default     = true
}

variable "mtls_client_cert" {
  description = "mTLS client certificate PEM (for Cloudflare to present to origin)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mtls_client_key" {
  description = "mTLS client private key PEM"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mtls_ca_cert" {
  description = "mTLS CA certificate PEM (for origin to verify Cloudflare)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "api_replicas" {
  description = "Number of API replicas"
  type        = number
  default     = 2
}

variable "repos_storage_size" {
  description = "Storage size for git repos"
  type        = string
  default     = "100Gi"
}

# -----------------------------------------------------------------------------
# Safety
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Enable deletion protection on critical resources"
  type        = bool
  default     = true
}
