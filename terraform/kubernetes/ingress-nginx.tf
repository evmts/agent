# =============================================================================
# Nginx Ingress Controller
# =============================================================================
# Deploys nginx-ingress via Helm for WebSocket support and routing.
# When enable_external_lb is false (edge mode), uses ClusterIP instead of LoadBalancer.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.9.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        replicaCount = 2

        service = var.enable_external_lb ? {
          # External LoadBalancer for direct public access
          type = "LoadBalancer"
          annotations = {
            "cloud.google.com/load-balancer-type" = "External"
          }
        } : {
          # ClusterIP for internal-only access (Cloudflare Tunnel)
          type = "ClusterIP"
        }

        config = {
          # WebSocket support
          "proxy-read-timeout"        = "3600"
          "proxy-send-timeout"        = "3600"
          "proxy-connect-timeout"     = "60"
          "proxy-body-size"           = "50m"
          "use-forwarded-headers"     = "true"
          "compute-full-forwarded-for" = "true"

          # Security (only force SSL when external LB is enabled)
          "ssl-redirect"              = var.enable_external_lb ? "true" : "false"
          "force-ssl-redirect"        = var.enable_external_lb ? "true" : "false"
          "hsts"                      = var.enable_external_lb ? "true" : "false"
          "hsts-max-age"              = "31536000"
          "hsts-include-subdomains"   = "true"
        }

        metrics = {
          enabled = true
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
    })
  ]

  wait = true
}

# Data source to get the LoadBalancer IP after deployment
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.ingress_nginx.namespace
  }

  depends_on = [helm_release.ingress_nginx]
}
