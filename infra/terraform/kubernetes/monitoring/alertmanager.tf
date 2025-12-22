# =============================================================================
# AlertManager Deployment
# =============================================================================
# AlertManager for alert routing and notification management.

# AlertManager ConfigMap
resource "kubernetes_config_map" "alertmanager" {
  metadata {
    name      = "alertmanager-config"
    namespace = var.namespace

    labels = {
      app        = "alertmanager"
      managed-by = "terraform"
    }
  }

  data = {
    "alertmanager.yml" = yamlencode({
      global = {
        resolve_timeout = "5m"
      }

      # Templates (optional)
      templates = []

      # Default route
      route = {
        group_by        = ["alertname", "cluster", "service"]
        group_wait      = "10s"
        group_interval  = "10s"
        repeat_interval = "12h"
        receiver        = "default"

        # Child routes for specific alerts
        routes = [
          {
            match = {
              severity = "critical"
            }
            receiver        = "critical"
            repeat_interval = "1h"
          },
          {
            match = {
              severity = "warning"
            }
            receiver        = "warning"
            repeat_interval = "4h"
          }
        ]
      }

      # Inhibition rules (suppress certain alerts when others fire)
      inhibit_rules = [
        {
          source_match = {
            severity = "critical"
          }
          target_match = {
            severity = "warning"
          }
          equal = ["alertname", "cluster", "service"]
        }
      ]

      # Receivers (placeholders for Slack/PagerDuty)
      receivers = [
        {
          name = "default"
          # Placeholder: Configure webhook_configs, email_configs, etc.
        },
        {
          name = "critical"
          # Placeholder: Add Slack webhook for critical alerts
          # slack_configs = [{
          #   api_url       = "SLACK_WEBHOOK_URL"
          #   channel       = "#critical-alerts"
          #   title         = "Critical: {{ .GroupLabels.alertname }}"
          #   text          = "{{ .CommonAnnotations.summary }}\n{{ .CommonAnnotations.description }}"
          #   send_resolved = true
          # }]
          # PagerDuty for critical alerts
          # pagerduty_configs = [{
          #   service_key  = "PAGERDUTY_INTEGRATION_KEY"
          #   description  = "{{ .CommonAnnotations.summary }}"
          #   severity     = "{{ .CommonLabels.severity }}"
          #   send_resolved = true
          # }]
        },
        {
          name = "warning"
          # Placeholder: Add Slack webhook for warnings
          # slack_configs = [{
          #   api_url       = "SLACK_WEBHOOK_URL"
          #   channel       = "#alerts"
          #   title         = "Warning: {{ .GroupLabels.alertname }}"
          #   text          = "{{ .CommonAnnotations.summary }}\n{{ .CommonAnnotations.description }}"
          #   send_resolved = true
          # }]
        }
      ]
    })
  }
}

# AlertManager Deployment
resource "kubernetes_deployment" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = var.namespace

    labels = {
      app        = "alertmanager"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "alertmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "alertmanager"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 65534 # nobody user
          fs_group        = 65534
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "alertmanager"
          image = "prom/alertmanager:v0.26.0"

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager",
            "--web.external-url=http://alertmanager:9093",
            "--cluster.advertise-address=0.0.0.0:9093"
          ]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false # AlertManager needs writable /alertmanager
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 9093
            name           = "http"
          }

          port {
            container_port = 9094
            name           = "cluster"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/alertmanager"
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9093
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9093
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.alertmanager.metadata[0].name
          }
        }

        volume {
          name = "storage"
          empty_dir {}
        }
      }
    }
  }
}

# AlertManager Service
resource "kubernetes_service" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = var.namespace

    labels = {
      app        = "alertmanager"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "alertmanager"
    }

    port {
      port        = 9093
      target_port = 9093
      name        = "http"
    }

    port {
      port        = 9094
      target_port = 9094
      name        = "cluster"
    }

    type = "ClusterIP"
  }
}
