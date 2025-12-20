# =============================================================================
# Grafana Deployment
# =============================================================================
# Grafana for metrics visualization and dashboards.

# Grafana ConfigMap - Datasources
resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  data = {
    "datasources.yaml" = yamlencode({
      apiVersion = 1
      datasources = [{
        name      = "Prometheus"
        type      = "prometheus"
        access    = "proxy"
        url       = "http://prometheus:9090"
        isDefault = true
        editable  = false
        jsonData = {
          timeInterval = "15s"
        }
      }]
    })
  }
}

# Grafana ConfigMap - Dashboards Provider
resource "kubernetes_config_map" "grafana_dashboard_provider" {
  metadata {
    name      = "grafana-dashboard-provider"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  data = {
    "dashboards.yaml" = yamlencode({
      apiVersion = 1
      providers = [{
        name            = "Default"
        orgId           = 1
        folder          = ""
        type            = "file"
        disableDeletion = false
        editable        = true
        options = {
          path = "/var/lib/grafana/dashboards"
        }
      }]
    })
  }
}

# Grafana ConfigMap - Default Dashboards
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  data = {
    "plue-overview.json" = jsonencode({
      title       = "Plue - System Overview"
      uid         = "plue-overview"
      description = "High-level overview of Plue infrastructure"
      editable    = true
      panels = [
        {
          id    = 1
          title = "CPU Usage by Service"
          type  = "graph"
          gridPos = {
            x = 0
            y = 0
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(rate(container_cpu_usage_seconds_total{namespace=\"plue\",pod!=\"\"}[5m])) by (pod)"
            legendFormat = "{{ pod }}"
          }]
        },
        {
          id    = 2
          title = "Memory Usage by Service"
          type  = "graph"
          gridPos = {
            x = 12
            y = 0
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(container_memory_working_set_bytes{namespace=\"plue\",pod!=\"\"}) by (pod)"
            legendFormat = "{{ pod }}"
          }]
        },
        {
          id    = 3
          title = "HTTP Request Rate"
          type  = "graph"
          gridPos = {
            x = 0
            y = 8
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(rate(http_requests_total{namespace=\"plue\"}[5m])) by (service)"
            legendFormat = "{{ service }}"
          }]
        },
        {
          id    = 4
          title = "HTTP Error Rate"
          type  = "graph"
          gridPos = {
            x = 12
            y = 8
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(rate(http_requests_total{namespace=\"plue\",status=~\"5..\"}[5m])) by (service)"
            legendFormat = "{{ service }} 5xx"
          }]
        },
        {
          id    = 5
          title = "Pod Status"
          type  = "stat"
          gridPos = {
            x = 0
            y = 16
            w = 6
            h = 4
          }
          targets = [{
            expr = "count(kube_pod_status_phase{namespace=\"plue\",phase=\"Running\"})"
          }]
        },
        {
          id    = 6
          title = "Active Alerts"
          type  = "stat"
          gridPos = {
            x = 6
            y = 16
            w = 6
            h = 4
          }
          targets = [{
            expr = "count(ALERTS{alertstate=\"firing\",namespace=\"plue\"})"
          }]
        },
        {
          id    = 7
          title = "Database Connections"
          type  = "graph"
          gridPos = {
            x = 12
            y = 16
            w = 12
            h = 8
          }
          targets = [{
            expr         = "db_connections_active{namespace=\"plue\"}"
            legendFormat = "Active Connections"
          }]
        }
      ]
    })

    "kubernetes-cluster.json" = jsonencode({
      title       = "Kubernetes Cluster"
      uid         = "kubernetes-cluster"
      description = "Kubernetes cluster resource usage"
      editable    = true
      panels = [
        {
          id    = 1
          title = "Node CPU Usage"
          type  = "graph"
          gridPos = {
            x = 0
            y = 0
            w = 12
            h = 8
          }
          targets = [{
            expr         = "100 - (avg by (node) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
            legendFormat = "{{ node }}"
          }]
        },
        {
          id    = 2
          title = "Node Memory Usage"
          type  = "graph"
          gridPos = {
            x = 12
            y = 0
            w = 12
            h = 8
          }
          targets = [{
            expr         = "100 * (1 - ((node_memory_MemAvailable_bytes) / (node_memory_MemTotal_bytes)))"
            legendFormat = "{{ node }}"
          }]
        },
        {
          id    = 3
          title = "Pod Count"
          type  = "stat"
          gridPos = {
            x = 0
            y = 8
            w = 6
            h = 4
          }
          targets = [{
            expr = "sum(kube_pod_info)"
          }]
        },
        {
          id    = 4
          title = "Node Count"
          type  = "stat"
          gridPos = {
            x = 6
            y = 8
            w = 6
            h = 4
          }
          targets = [{
            expr = "sum(kube_node_info)"
          }]
        },
        {
          id    = 5
          title = "Persistent Volume Usage"
          type  = "graph"
          gridPos = {
            x = 12
            y = 8
            w = 12
            h = 8
          }
          targets = [{
            expr         = "100 * (kubelet_volume_stats_used_bytes{namespace=\"plue\"} / kubelet_volume_stats_capacity_bytes{namespace=\"plue\"})"
            legendFormat = "{{ persistentvolumeclaim }}"
          }]
        }
      ]
    })

    "api-performance.json" = jsonencode({
      title       = "API Performance"
      uid         = "api-performance"
      description = "API service performance metrics"
      editable    = true
      panels = [
        {
          id    = 1
          title = "Request Rate"
          type  = "graph"
          gridPos = {
            x = 0
            y = 0
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(rate(http_requests_total{service=\"api\"}[5m])) by (method, path)"
            legendFormat = "{{ method }} {{ path }}"
          }]
        },
        {
          id    = 2
          title = "Response Time (p50, p95, p99)"
          type  = "graph"
          gridPos = {
            x = 12
            y = 0
            w = 12
            h = 8
          }
          targets = [
            {
              expr         = "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service=\"api\"}[5m])) by (le))"
              legendFormat = "p50"
            },
            {
              expr         = "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"api\"}[5m])) by (le))"
              legendFormat = "p95"
            },
            {
              expr         = "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"api\"}[5m])) by (le))"
              legendFormat = "p99"
            }
          ]
        },
        {
          id    = 3
          title = "Error Rate by Status Code"
          type  = "graph"
          gridPos = {
            x = 0
            y = 8
            w = 12
            h = 8
          }
          targets = [{
            expr         = "sum(rate(http_requests_total{service=\"api\",status=~\"[45]..\"}[5m])) by (status)"
            legendFormat = "{{ status }}"
          }]
        },
        {
          id    = 4
          title = "Active Connections"
          type  = "graph"
          gridPos = {
            x = 12
            y = 8
            w = 12
            h = 8
          }
          targets = [{
            expr         = "http_connections_active{service=\"api\"}"
            legendFormat = "Active Connections"
          }]
        }
      ]
    })
  }
}

# Grafana Secret
resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana-admin"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  data = {
    admin-password = base64encode(var.grafana_admin_password)
  }

  type = "Opaque"
}

# Grafana PersistentVolumeClaim
resource "kubernetes_persistent_volume_claim" "grafana" {
  metadata {
    name      = "grafana-storage"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "ssd"

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# Grafana Deployment
resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 472 # grafana user
          fs_group        = 472
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "grafana"
          image = "grafana/grafana:10.2.2"

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false # Grafana needs writable filesystem
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }

          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana.metadata[0].name
                key  = "admin-password"
              }
            }
          }

          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://grafana.${var.domain}"
          }

          env {
            name  = "GF_INSTALL_PLUGINS"
            value = ""
          }

          volume_mount {
            name       = "storage"
            mount_path = "/var/lib/grafana"
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
          }

          volume_mount {
            name       = "dashboard-provider"
            mount_path = "/etc/grafana/provisioning/dashboards"
          }

          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana/dashboards"
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana.metadata[0].name
          }
        }

        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata[0].name
          }
        }

        volume {
          name = "dashboard-provider"
          config_map {
            name = kubernetes_config_map.grafana_dashboard_provider.metadata[0].name
          }
        }

        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map.grafana_dashboards.metadata[0].name
          }
        }
      }
    }
  }
}

# Grafana Service
resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 3000
      target_port = 3000
      name        = "http"
    }

    type = "ClusterIP"
  }
}
