# =============================================================================
# Ingress Configuration
# =============================================================================
# Routes traffic to web, api, electric, and adminer services.

resource "kubernetes_ingress_v1" "plue" {
  metadata {
    name      = "plue-ingress"
    namespace = kubernetes_namespace.plue.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class" = "nginx"

      # Body size for file uploads
      "nginx.ingress.kubernetes.io/proxy-body-size" = "50m"

      # WebSocket support (extended timeouts)
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "3600"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "60"

      # Connection upgrade for WebSockets
      "nginx.ingress.kubernetes.io/upstream-hash-by" = "$request_uri"

      # SSL redirect
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"

      # CORS (if needed, usually handled by app)
      # "nginx.ingress.kubernetes.io/enable-cors" = "true"
    }

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  spec {
    ingress_class_name = "nginx"

    # TLS configuration
    tls {
      hosts = [
        var.domain,
        "api.${var.domain}",
        "electric.${var.domain}",
      ]
      # Note: When using Cloudflare proxy, Cloudflare handles SSL
      # If using cert-manager, uncomment:
      # secret_name = "plue-tls"
    }

    # Web frontend (main domain)
    rule {
      host = var.domain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.web.metadata[0].name
              port {
                number = 5173
              }
            }
          }
        }
      }
    }

    # API service
    rule {
      host = "api.${var.domain}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.api.metadata[0].name
              port {
                number = 4000
              }
            }
          }
        }
      }
    }

    # ElectricSQL service
    rule {
      host = "electric.${var.domain}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.electric.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    # SECURITY: Adminer removed from public ingress to prevent unauthorized database access.
    # For admin access to the database, use kubectl port-forward:
    # kubectl port-forward -n plue svc/adminer 8080:8080
    # Then access at http://localhost:8080
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_deployment.web,
    kubernetes_deployment.api,
    kubernetes_deployment.electric,
    kubernetes_deployment.adminer,
  ]
}
