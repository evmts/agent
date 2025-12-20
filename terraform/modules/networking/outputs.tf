# =============================================================================
# Networking Module Outputs
# =============================================================================

output "vpc_id" {
  description = "The VPC network ID"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "The VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "The VPC network self link"
  value       = google_compute_network.vpc.self_link
}

output "gke_subnet_id" {
  description = "The GKE subnet ID"
  value       = google_compute_subnetwork.gke.id
}

output "gke_subnet_name" {
  description = "The GKE subnet name"
  value       = google_compute_subnetwork.gke.name
}

output "gke_subnet_self_link" {
  description = "The GKE subnet self link"
  value       = google_compute_subnetwork.gke.self_link
}

output "private_vpc_connection" {
  description = "Private service connection for Cloud SQL"
  value       = google_service_networking_connection.private_vpc_connection.id
}

output "pods_secondary_range_name" {
  description = "Name of the pods secondary range"
  value       = "pods"
}

output "services_secondary_range_name" {
  description = "Name of the services secondary range"
  value       = "services"
}
