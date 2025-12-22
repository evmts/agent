# =============================================================================
# Prometheus Deployment
# =============================================================================
# Prometheus for metrics collection and monitoring.

# Prometheus Alerts ConfigMap
resource "kubernetes_config_map" "prometheus_alerts" {
  metadata {
    name      = "prometheus-alerts"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  data = {
    "alerts.yaml" = file("${path.module}/alerts.yaml")
  }
}

# Prometheus ConfigMap
resource "kubernetes_config_map" "prometheus" {
  metadata {
    name      = "prometheus-config"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  data = {
    "prometheus.yml" = yamlencode({
      global = {
        scrape_interval     = "15s"
        evaluation_interval = "15s"
        external_labels = {
          cluster   = "plue-production"
          namespace = var.namespace
        }
      }

      # AlertManager configuration
      alerting = {
        alertmanagers = [{
          static_configs = [{
            targets = ["alertmanager:9093"]
          }]
        }]
      }

      # Load alert rules
      rule_files = [
        "/etc/prometheus/alerts/*.yaml"
      ]

      # Scrape configurations
      scrape_configs = [
        # Prometheus self-monitoring
        {
          job_name = "prometheus"
          static_configs = [{
            targets = ["localhost:9090"]
          }]
        },

        # Kubernetes API Server
        {
          job_name = "kubernetes-apiservers"
          kubernetes_sd_configs = [{
            role = "endpoints"
          }]
          scheme = "https"
          tls_config = {
            ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
          }
          bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
          relabel_configs = [{
            source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_service_name", "__meta_kubernetes_endpoint_port_name"]
            action        = "keep"
            regex         = "default;kubernetes;https"
          }]
        },

        # Kubernetes Nodes
        {
          job_name = "kubernetes-nodes"
          kubernetes_sd_configs = [{
            role = "node"
          }]
          scheme = "https"
          tls_config = {
            ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
          }
          bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
          relabel_configs = [{
            action = "labelmap"
            regex  = "__meta_kubernetes_node_label_(.+)"
          }]
        },

        # Kubernetes Pods
        {
          job_name = "kubernetes-pods"
          kubernetes_sd_configs = [{
            role = "pod"
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
              action        = "keep"
              regex         = true
            },
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
              action        = "replace"
              target_label  = "__metrics_path__"
              regex         = "(.+)"
            },
            {
              source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
              action        = "replace"
              regex         = "([^:]+)(?::\\d+)?;(\\d+)"
              replacement   = "$1:$2"
              target_label  = "__address__"
            },
            {
              action = "labelmap"
              regex  = "__meta_kubernetes_pod_label_(.+)"
            },
            {
              source_labels = ["__meta_kubernetes_namespace"]
              action        = "replace"
              target_label  = "kubernetes_namespace"
            },
            {
              source_labels = ["__meta_kubernetes_pod_name"]
              action        = "replace"
              target_label  = "kubernetes_pod_name"
            }
          ]
        },

        # API Service
        {
          job_name = "api"
          kubernetes_sd_configs = [{
            role      = "pod"
            namespaces = {
              names = [var.namespace]
            }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              action        = "keep"
              regex         = "api"
            },
            {
              source_labels = ["__meta_kubernetes_pod_ip"]
              action        = "replace"
              target_label  = "__address__"
              replacement   = "$1:4000"
            },
            {
              action       = "replace"
              target_label = "__metrics_path__"
              replacement  = "/metrics"
            }
          ]
        },

        # Web Service
        {
          job_name = "web"
          kubernetes_sd_configs = [{
            role      = "pod"
            namespaces = {
              names = [var.namespace]
            }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              action        = "keep"
              regex         = "web"
            },
            {
              source_labels = ["__meta_kubernetes_pod_ip"]
              action        = "replace"
              target_label  = "__address__"
              replacement   = "$1:5173"
            },
            {
              action       = "replace"
              target_label = "__metrics_path__"
              replacement  = "/metrics"
            }
          ]
        },

        # Electric Service
        {
          job_name = "electric"
          kubernetes_sd_configs = [{
            role      = "pod"
            namespaces = {
              names = [var.namespace]
            }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              action        = "keep"
              regex         = "electric"
            },
            {
              source_labels = ["__meta_kubernetes_pod_ip"]
              action        = "replace"
              target_label  = "__address__"
              replacement   = "$1:3000"
            },
            {
              action       = "replace"
              target_label = "__metrics_path__"
              replacement  = "/metrics"
            }
          ]
        }
      ]
    })
  }
}

# Prometheus PersistentVolumeClaim
resource "kubernetes_persistent_volume_claim" "prometheus" {
  metadata {
    name      = "prometheus-storage"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "ssd"

    resources {
      requests = {
        storage = var.prometheus_storage_size
      }
    }
  }
}

# Prometheus Deployment
resource "kubernetes_deployment" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prometheus"
      }
    }

    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.prometheus.metadata[0].name

        security_context {
          run_as_non_root = true
          run_as_user     = 65534 # nobody user
          fs_group        = 65534
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "prometheus"
          image = "prom/prometheus:v2.48.0"

          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=${var.prometheus_retention}",
            "--web.console.libraries=/usr/share/prometheus/console_libraries",
            "--web.console.templates=/usr/share/prometheus/consoles",
            "--web.enable-lifecycle"
          ]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false # Prometheus needs writable /prometheus
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 9090
            name           = "http"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
          }

          volume_mount {
            name       = "alerts"
            mount_path = "/etc/prometheus/alerts"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/prometheus"
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9090
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus.metadata[0].name
          }
        }

        volume {
          name = "alerts"
          config_map {
            name = kubernetes_config_map.prometheus_alerts.metadata[0].name
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus.metadata[0].name
          }
        }
      }
    }
  }
}

# Prometheus Service
resource "kubernetes_service" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "prometheus"
    }

    port {
      port        = 9090
      target_port = 9090
      name        = "http"
    }

    type = "ClusterIP"
  }
}

# Prometheus ServiceAccount
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }
}

# Prometheus ClusterRole
resource "kubernetes_cluster_role" "prometheus" {
  metadata {
    name = "prometheus"

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

# Prometheus ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "prometheus" {
  metadata {
    name = "prometheus"

    labels = {
      app        = "prometheus"
      managed-by = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.prometheus.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus.metadata[0].name
    namespace = var.namespace
  }
}
