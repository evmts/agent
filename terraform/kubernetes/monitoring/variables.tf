# =============================================================================
# Monitoring Module Variables
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for monitoring stack"
  type        = string
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size"
  type        = string
  default     = "50Gi"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "alertmanager_slack_webhook" {
  description = "Slack webhook URL for alerts (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alertmanager_pagerduty_key" {
  description = "PagerDuty integration key (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain" {
  description = "Domain for Grafana ingress"
  type        = string
}

variable "alert_cpu_threshold" {
  description = "CPU usage alert threshold (percent)"
  type        = number
  default     = 80
}

variable "alert_memory_threshold" {
  description = "Memory usage alert threshold (percent)"
  type        = number
  default     = 80
}

variable "alert_error_rate_threshold" {
  description = "HTTP 5xx error rate threshold (percent)"
  type        = number
  default     = 1
}
