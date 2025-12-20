# =============================================================================
# GKE Module
# =============================================================================
# Creates a GKE Standard cluster with node pools for Plue workloads.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# GKE Node Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.name_prefix}-gke-nodes"
  display_name = "GKE Node Service Account"
  description  = "Service account for GKE nodes"
  project      = var.project_id
}

# Minimal permissions for nodes
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_stackdriver_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# -----------------------------------------------------------------------------
# GKE Cluster
# -----------------------------------------------------------------------------

resource "google_container_cluster" "primary" {
  name     = "${var.name_prefix}-cluster"
  project  = var.project_id
  location = var.region

  # Regional cluster for HA (nodes spread across zones)
  node_locations = var.node_zones

  # VPC-native cluster
  network    = var.vpc_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Allow kubectl from internet (with auth)
    master_ipv4_cidr_block  = var.master_cidr
  }

  # Master authorized networks (restrict kubectl access)
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Remove default node pool, we'll create our own
  remove_default_node_pool = true
  initial_node_count       = 1

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  # Binary Authorization
  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Dataplane V2 (includes built-in network policy)
  datapath_provider = "ADVANCED_DATAPATH"

  # Logging
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Monitoring
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Maintenance window (Sunday 2-6 AM)
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  # Security
  enable_shielded_nodes = true

  resource_labels = var.labels

  # Prevent accidental deletion
  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      # Node pool is managed separately
      node_pool,
      initial_node_count,
    ]
  }
}

# -----------------------------------------------------------------------------
# Primary Node Pool
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "primary" {
  name       = "primary-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.primary_pool_initial_size

  autoscaling {
    min_node_count = var.primary_pool_min_size
    max_node_count = var.primary_pool_max_size
  }

  node_config {
    machine_type = var.primary_machine_type
    disk_size_gb = var.primary_disk_size_gb
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.gke_nodes.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      pool = "primary"
    }

    tags = ["gke-node", "${var.name_prefix}-gke-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  lifecycle {
    ignore_changes = [
      # Allow autoscaler to manage node count
      node_count,
    ]
  }
}
