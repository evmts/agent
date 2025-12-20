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
  description = "Enable Cloudflare Workers edge deployment with Electric caching"
  type        = bool
  default     = false
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

# -----------------------------------------------------------------------------
# Safety
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Enable deletion protection on critical resources"
  type        = bool
  default     = true
}
