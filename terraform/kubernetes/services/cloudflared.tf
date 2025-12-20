# =============================================================================
# Cloudflared Tunnel Daemon Deployment
# =============================================================================
# Runs cloudflared inside GKE to establish secure tunnel to Cloudflare.
# This is the ONLY way traffic reaches the private GKE cluster.

resource "kubernetes_secret" "cloudflared_credentials" {
  count = var.enable_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared-credentials"
    namespace = var.namespace

    labels = {
      app        = "cloudflared"
      managed-by = "terraform"
    }
  }

  data = {
    # Tunnel token from Cloudflare Tunnel module
    "tunnel-token" = var.cloudflare_tunnel_token
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "cloudflared" {
  count = var.enable_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared"
    namespace = var.namespace

    labels = {
      app        = "cloudflared"
      managed-by = "terraform"
    }
  }

  spec {
    replicas = 2 # Run 2 replicas for high availability

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        service_account_name = var.service_account_name

        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"

          args = [
            "tunnel",
            "--no-autoupdate",
            "run",
            "--token",
            "$(TUNNEL_TOKEN)"
          ]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflared_credentials[0].metadata[0].name
                key  = "tunnel-token"
              }
            }
          }

          # Health check via metrics endpoint
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 2000
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
              memory = "256Mi"
            }
          }

          # Enable metrics endpoint for health checks
          port {
            container_port = 2000
            name           = "metrics"
          }
        }

        # Spread across nodes for HA
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    app = "cloudflared"
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        # Restart on failure
        restart_policy = "Always"
      }
    }
  }
}

# Optional: Service for metrics scraping
resource "kubernetes_service" "cloudflared_metrics" {
  count = var.enable_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared-metrics"
    namespace = var.namespace

    labels = {
      app        = "cloudflared"
      managed-by = "terraform"
    }
  }

  spec {
    selector = {
      app = "cloudflared"
    }

    port {
      port        = 2000
      target_port = 2000
      name        = "metrics"
    }

    type = "ClusterIP"
  }
}
