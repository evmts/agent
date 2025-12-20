# =============================================================================
# API Server Deployment
# =============================================================================
# Zig API server with WebSocket support for PTY terminals.

resource "kubernetes_deployment" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace

    labels = {
      app        = "api"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = var.api_replicas

    selector {
      match_labels = {
        app = "api"
      }
    }

    template {
      metadata {
        labels = {
          app = "api"
        }
      }

      spec {
        service_account_name = var.service_account_name

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "api"
          image = "${var.registry_url}/plue-api:${var.image_tag}"

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 4000
            name           = "http"
          }

          env {
            name  = "PORT"
            value = "4000"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "database-url"
                key  = "url"
              }
            }
          }

          env {
            name  = "ELECTRIC_URL"
            value = "http://electric:3000"
          }

          env {
            name = "ANTHROPIC_API_KEY"
            value_from {
              secret_key_ref {
                name = "anthropic-api-key"
                key  = "key"
              }
            }
          }

          env {
            name = "SESSION_SECRET"
            value_from {
              secret_key_ref {
                name = "session-secret"
                key  = "secret"
              }
            }
          }

          env {
            name  = "SECURE_COOKIES"
            value = "true"
          }

          env {
            name = "EDGE_PUSH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.edge_push_secret.metadata[0].name
                key  = "secret"
              }
            }
          }

          env {
            name  = "EDGE_URL"
            value = "https://plue-edge.${var.domain}"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace

    labels = {
      app        = "api"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "api"
    }

    port {
      port        = 4000
      target_port = 4000
      name        = "http"
    }

    type = "ClusterIP"
  }
}

# Horizontal Pod Autoscaler for API
resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.api.metadata[0].name
    }

    min_replicas = var.api_replicas
    max_replicas = var.api_replicas * 3

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }
  }
}
