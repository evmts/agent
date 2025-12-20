# =============================================================================
# Networking Module
# =============================================================================
# Creates VPC, subnets, Cloud NAT, and Private Service Access for Cloud SQL.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC Network
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# -----------------------------------------------------------------------------
# GKE Subnet with Secondary Ranges
# -----------------------------------------------------------------------------

resource "google_compute_subnetwork" "gke" {
  name          = "${var.name_prefix}-gke-subnet"
  project       = var.project_id
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = var.gke_subnet_cidr

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# -----------------------------------------------------------------------------
# Private Service Access (for Cloud SQL)
# -----------------------------------------------------------------------------

resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.name_prefix}-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  deletion_policy = "ABANDON"
}

# -----------------------------------------------------------------------------
# Cloud Router (for Cloud NAT)
# -----------------------------------------------------------------------------

resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# -----------------------------------------------------------------------------
# Cloud NAT (for private nodes to reach internet)
# -----------------------------------------------------------------------------

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# Firewall Rules
# -----------------------------------------------------------------------------

# Allow internal communication within VPC
resource "google_compute_firewall" "internal" {
  name    = "${var.name_prefix}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.gke_subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ]
}

# Allow health checks from GCP load balancers
resource "google_compute_firewall" "health_checks" {
  name    = "${var.name_prefix}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  # GCP health check IP ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  target_tags = ["gke-node"]
}

# Allow SSH from IAP (for debugging)
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP IP range
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["gke-node"]
}
