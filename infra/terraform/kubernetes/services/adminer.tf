# =============================================================================
# Adminer Deployment
# =============================================================================
# Database admin UI for development/debugging.

resource "kubernetes_deployment" "adminer" {
  metadata {
    name      = "adminer"
    namespace = var.namespace

    labels = {
      app        = "adminer"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "adminer"
      }
    }

    template {
      metadata {
        labels = {
          app = "adminer"
        }
      }

      spec {
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
          name  = "adminer"
          image = "adminer:4.8.1"

          security_context {
            allow_privilege_escalation = false
            # Note: Cannot use read_only_root_filesystem as Adminer (PHP/Apache) needs to write session and temp files
            read_only_root_filesystem = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "ADMINER_DEFAULT_SERVER"
            value = var.database_host
          }

          env {
            name  = "ADMINER_DESIGN"
            value = "dracula"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "adminer" {
  metadata {
    name      = "adminer"
    namespace = var.namespace

    labels = {
      app        = "adminer"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "adminer"
    }

    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }

    type = "ClusterIP"
  }
}
