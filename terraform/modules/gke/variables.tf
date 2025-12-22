# =============================================================================
# GKE Module Variables
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

variable "node_zones" {
  description = "Zones for GKE nodes"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC network ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for GKE nodes"
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the secondary range for services"
  type        = string
}

variable "master_cidr" {
  description = "CIDR block for the GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "Networks authorized to access the GKE master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All (use with caution)"
    }
  ]
}

# Primary node pool configuration
variable "primary_machine_type" {
  description = "Machine type for primary node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "primary_disk_size_gb" {
  description = "Disk size for primary node pool nodes"
  type        = number
  default     = 100
}

variable "primary_pool_initial_size" {
  description = "Initial number of nodes per zone in primary pool"
  type        = number
  default     = 1
}

variable "primary_pool_min_size" {
  description = "Minimum number of nodes per zone in primary pool"
  type        = number
  default     = 1
}

variable "primary_pool_max_size" {
  description = "Maximum number of nodes per zone in primary pool"
  type        = number
  default     = 5
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion"
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

# =============================================================================
# Sandbox Node Pool (gVisor) - for agent/workflow execution
# =============================================================================

variable "enable_sandbox_pool" {
  description = "Enable sandbox node pool with gVisor for agent execution"
  type        = bool
  default     = false
}

variable "sandbox_machine_type" {
  description = "Machine type for sandbox node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "sandbox_disk_size_gb" {
  description = "Disk size for sandbox node pool nodes"
  type        = number
  default     = 100
}

variable "sandbox_pool_min_size" {
  description = "Minimum number of nodes per zone in sandbox pool"
  type        = number
  default     = 1
}

variable "sandbox_pool_max_size" {
  description = "Maximum number of nodes per zone in sandbox pool"
  type        = number
  default     = 10
}
