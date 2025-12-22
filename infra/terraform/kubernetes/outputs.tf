# =============================================================================
# Kubernetes Module Outputs
# =============================================================================

output "namespace" {
  description = "The Kubernetes namespace"
  value       = kubernetes_namespace.plue.metadata[0].name
}

output "service_account_name" {
  description = "The Kubernetes service account name"
  value       = kubernetes_service_account.workload.metadata[0].name
}

output "load_balancer_ip" {
  description = "The LoadBalancer IP address"
  value       = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}
