# =============================================================================
# Database Migration Job
# =============================================================================
# Applies schema.sql to PostgreSQL on first deployment.

resource "kubernetes_config_map" "db_schema" {
  metadata {
    name      = "db-schema"
    namespace = var.namespace

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  data = {
    "schema.sql" = file(var.schema_file_path)
  }
}

resource "kubernetes_job" "db_migrate" {
  metadata {
    name      = "db-migrate-${var.schema_hash}"
    namespace = var.namespace

    labels = {
      app        = "plue"
      job        = "db-migrate"
      managed-by = "terraform"
    }
  }

  spec {
    ttl_seconds_after_finished = 3600 # Clean up after 1 hour

    template {
      metadata {
        labels = {
          app = "plue"
          job = "db-migrate"
        }
      }

      spec {
        restart_policy       = "OnFailure"
        service_account_name = var.service_account_name

        container {
          name  = "migrate"
          image = "postgres:16-alpine"

          command = ["sh", "-c"]
          args    = ["psql \"$DATABASE_URL\" -f /schema/schema.sql"]

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "database-url"
                key  = "url"
              }
            }
          }

          volume_mount {
            name       = "schema"
            mount_path = "/schema"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "schema"
          config_map {
            name = kubernetes_config_map.db_schema.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }
}
