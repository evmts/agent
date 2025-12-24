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
  description = <<-EOT
    Networks authorized to access the GKE master API.

    SECURITY: Never use 0.0.0.0/0 in production - this exposes the Kubernetes
    API to the entire internet. Always specify trusted networks explicitly.

    Common authorized networks:
    - Google Cloud Shell: 35.235.240.0/20
    - GitHub Actions runners: Dynamic IPs (see GitHub's IP ranges)
    - Office/VPN: Your organization's egress IPs
    - CI/CD systems: Your build infrastructure IPs

    Fallback access: If locked out, you can always access via Cloud Shell,
    which is pre-authorized in Google Cloud Console.
  EOT

  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  # Force explicit configuration - no default authorized networks
  default = []

  validation {
    condition = alltrue([
      for network in var.master_authorized_networks :
      network.cidr_block != "0.0.0.0/0"
    ])
    error_message = <<-EOT
      SECURITY VIOLATION: 0.0.0.0/0 is not allowed in master_authorized_networks.

      Exposing the Kubernetes API to the entire internet is a critical security risk.
      Please specify trusted networks explicitly:

      master_authorized_networks = [
        {
          cidr_block   = "35.235.240.0/20"
          display_name = "Google Cloud Shell"
        },
        {
          cidr_block   = "YOUR_OFFICE_IP/32"
          display_name = "Office Network"
        }
      ]

      If you need emergency access, use Google Cloud Shell from the GCP Console.
    EOT
  }
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
