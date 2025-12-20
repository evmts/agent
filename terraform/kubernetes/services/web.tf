# =============================================================================
# Web Frontend Deployment
# =============================================================================
# Astro SSR frontend with persistent storage for git repos.

resource "kubernetes_persistent_volume_claim" "repos_storage" {
  metadata {
    name      = "repos-storage"
    namespace = var.namespace

    labels = {
      app        = "web"
      managed-by = "terraform"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "ssd-retain" # Retain on delete to preserve repos

    resources {
      requests = {
        storage = var.repos_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "web" {
  metadata {
    name      = "web"
    namespace = var.namespace

    labels = {
      app        = "web"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1 # Single replica due to RWO PVC constraint

    strategy {
      type = "Recreate" # Required for RWO PVC
    }

    selector {
      match_labels = {
        app = "web"
      }
    }

    template {
      metadata {
        labels = {
          app = "web"
        }
      }

      spec {
        service_account_name = var.service_account_name

        # Init container to set up git config
        init_container {
          name  = "init-git"
          image = "alpine/git:latest"

          command = ["sh", "-c"]
          args    = ["git config --global user.email 'plue@localhost' && git config --global user.name 'Plue' && git config --global init.defaultBranch main"]

          volume_mount {
            name       = "repos"
            mount_path = "/app/repos"
          }
        }

        container {
          name  = "web"
          image = "${var.registry_url}/plue-web:${var.image_tag}"

          port {
            container_port = 5173
            name           = "http"
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "PORT"
            value = "5173"
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

          # Internal service URLs (SSR)
          env {
            name  = "PUBLIC_API_URL"
            value = "http://api:4000"
          }

          env {
            name  = "PUBLIC_ELECTRIC_URL"
            value = "http://electric:3000"
          }

          # External URLs (browser)
          env {
            name  = "PUBLIC_CLIENT_API_URL"
            value = "https://api.${var.domain}"
          }

          env {
            name  = "PUBLIC_CLIENT_ELECTRIC_URL"
            value = "https://electric.${var.domain}"
          }

          env {
            name  = "SITE_URL"
            value = "https://${var.domain}"
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

          volume_mount {
            name       = "repos"
            mount_path = "/app/repos"
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5173
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5173
            }
            initial_delay_seconds = 10
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
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }

        volume {
          name = "repos"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.repos_storage.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "web" {
  metadata {
    name      = "web"
    namespace = var.namespace

    labels = {
      app        = "web"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "web"
    }

    port {
      port        = 5173
      target_port = 5173
      name        = "http"
    }

    type = "ClusterIP"
  }
}
