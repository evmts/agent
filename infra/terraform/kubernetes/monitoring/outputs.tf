# =============================================================================
# Monitoring Outputs
# =============================================================================

output "prometheus_service_name" {
  description = "Prometheus service name"
  value       = kubernetes_service.prometheus.metadata[0].name
}

output "prometheus_service_port" {
  description = "Prometheus service port"
  value       = kubernetes_service.prometheus.spec[0].port[0].port
}

output "alertmanager_service_name" {
  description = "AlertManager service name"
  value       = kubernetes_service.alertmanager.metadata[0].name
}

output "alertmanager_service_port" {
  description = "AlertManager service port"
  value       = kubernetes_service.alertmanager.spec[0].port[0].port
}

output "grafana_service_name" {
  description = "Grafana service name"
  value       = kubernetes_service.grafana.metadata[0].name
}

output "grafana_service_port" {
  description = "Grafana service port"
  value       = kubernetes_service.grafana.spec[0].port[0].port
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "https://grafana.${var.domain}"
}

output "monitoring_namespace" {
  description = "Monitoring namespace"
  value       = var.namespace
}
