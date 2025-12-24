# =============================================================================
# Staging Environment Variables
# =============================================================================

# -----------------------------------------------------------------------------
# GCP Project
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Human-readable project name"
  type        = string
  default     = "Plue Staging"
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
  default     = "10.1.0.0/20"  # Different from production
}

variable "pods_cidr" {
  description = "CIDR for GKE pods"
  type        = string
  default     = "10.12.0.0/14"  # Different from production
}

variable "services_cidr" {
  description = "CIDR for GKE services"
  type        = string
  default     = "10.16.0.0/20"  # Different from production
}

# -----------------------------------------------------------------------------
# GKE
# -----------------------------------------------------------------------------

variable "gke_node_zones" {
  description = "Zones for GKE nodes"
  type        = list(string)
  default     = ["us-west1-a"]  # Single zone for staging
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"  # Smaller for staging
}

variable "gke_min_nodes" {
  description = "Minimum nodes per zone"
  type        = number
  default     = 1
}

variable "gke_max_nodes" {
  description = "Maximum nodes per zone"
  type        = number
  default     = 3  # Lower limit for staging
}

# -----------------------------------------------------------------------------
# GKE Sandbox Pool (for workflow runners)
# -----------------------------------------------------------------------------

variable "enable_sandbox_pool" {
  description = "Enable gVisor sandbox node pool for workflow runners"
  type        = bool
  default     = true  # Enable by default for staging
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
  default     = 5
}

# -----------------------------------------------------------------------------
# Cloud SQL
# -----------------------------------------------------------------------------

variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"  # Smallest for staging
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 10  # Minimal for staging
}

variable "db_ha_enabled" {
  description = "Enable Cloud SQL regional HA"
  type        = bool
  default     = false  # No HA for staging
}

# -----------------------------------------------------------------------------
# Domain & DNS
# -----------------------------------------------------------------------------

variable "domain" {
  description = "Domain name for the application"
  type        = string
}

variable "subdomain" {
  description = "Subdomain (e.g., 'staging' for staging.plue.dev)"
  type        = string
  default     = "staging"
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

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "staging"
}

variable "api_replicas" {
  description = "Number of API replicas"
  type        = number
  default     = 1  # Single replica for staging
}

variable "repos_storage_size" {
  description = "Storage size for git repos"
  type        = string
  default     = "20Gi"  # Smaller for staging
}

# -----------------------------------------------------------------------------
# Safety
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Enable deletion protection on critical resources"
  type        = bool
  default     = false  # Allow deletion in staging
}
