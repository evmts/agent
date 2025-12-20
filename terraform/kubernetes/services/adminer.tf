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
        container {
          name  = "adminer"
          image = "adminer:latest"

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
