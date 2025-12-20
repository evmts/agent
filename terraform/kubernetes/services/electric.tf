# =============================================================================
# ElectricSQL Deployment
# =============================================================================
# ElectricSQL sync service with persistent storage.

resource "kubernetes_persistent_volume_claim" "electric_storage" {
  metadata {
    name      = "electric-storage"
    namespace = var.namespace

    labels = {
      app        = "electric"
      managed-by = "terraform"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "ssd"

    resources {
      requests = {
        storage = var.electric_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "electric" {
  metadata {
    name      = "electric"
    namespace = var.namespace

    labels = {
      app        = "electric"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 1 # ElectricSQL is stateful, single replica

    selector {
      match_labels = {
        app = "electric"
      }
    }

    template {
      metadata {
        labels = {
          app = "electric"
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
          name  = "electric"
          image = "electricsql/electric:0.9.0"

          security_context {
            allow_privilege_escalation = false
            # Note: Cannot use read_only_root_filesystem as ElectricSQL needs to write to storage volume
            # The service maintains sync state in /var/lib/electric
            read_only_root_filesystem = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 3000
            name           = "http"
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
            name  = "ELECTRIC_WRITE_TO_PG_MODE"
            value = "direct_writes"
          }

          env {
            name  = "ELECTRIC_STORAGE_DIR"
            value = "/var/lib/electric"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/var/lib/electric"
          }

          liveness_probe {
            http_get {
              path = "/v1/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/v1/health"
              port = 3000
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
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.electric_storage.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "electric" {
  metadata {
    name      = "electric"
    namespace = var.namespace

    labels = {
      app        = "electric"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "electric"
    }

    port {
      port        = 3000
      target_port = 3000
      name        = "http"
    }

    type = "ClusterIP"
  }
}
