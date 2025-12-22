# =============================================================================
# Kubernetes NetworkPolicies
# =============================================================================
# Implements least-privilege networking to restrict pod-to-pod communication
# and prevent lateral movement in case of pod compromise.
#
# Network Flow Architecture:
#   Internet → Cloudflare/LB → Ingress Controller → Services → Database
#
# Security Model:
#   - Default deny all ingress/egress
#   - Explicit allow only required communication
#   - Isolate database from direct external access
#   - Prevent lateral movement between services

# =============================================================================
# Default Deny All Policy
# =============================================================================
# Denies all ingress and egress traffic by default.
# All other policies are explicit allowlists on top of this.

resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = var.namespace

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  spec {
    # Apply to all pods in the namespace
    pod_selector {}

    # Deny both ingress and egress by default
    policy_types = ["Ingress", "Egress"]
  }
}

# =============================================================================
# API Service Network Policy
# =============================================================================
# API server needs:
#   Ingress: from ingress-nginx, web service, cloudflared
#   Egress: to database, electric, external APIs (Claude API, webhooks)

resource "kubernetes_network_policy" "api_policy" {
  metadata {
    name      = "api-network-policy"
    namespace = var.namespace

    labels = {
      app        = "api"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "api"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from ingress-nginx controller
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        port     = "4000"
        protocol = "TCP"
      }
    }

    # Allow ingress from web service (for SSR API calls)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "web"
          }
        }
      }
      ports {
        port     = "4000"
        protocol = "TCP"
      }
    }

    # Allow ingress from cloudflared (if enabled)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "cloudflared"
          }
        }
      }
      ports {
        port     = "4000"
        protocol = "TCP"
      }
    }

    # Allow egress to database (PostgreSQL)
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow egress to ElectricSQL
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "electric"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow egress to external APIs (Claude API, webhooks, etc.)
    # Note: This allows ALL external HTTPS traffic. For stricter security,
    # consider using Istio/Linkerd to restrict by domain.
    egress {
      to {
        # Allow egress to external IPs (internet)
        # This is necessary for Claude API and webhook callbacks
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            # Exclude internal cluster networks
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
          ]
        }
      }
      ports {
        port     = "443"
        protocol = "TCP"
      }
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Web Service Network Policy
# =============================================================================
# Web frontend needs:
#   Ingress: from ingress-nginx, cloudflared
#   Egress: to API service, electric service, database (for SSR)

resource "kubernetes_network_policy" "web_policy" {
  metadata {
    name      = "web-network-policy"
    namespace = var.namespace

    labels = {
      app        = "web"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "web"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from ingress-nginx controller
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        port     = "5173"
        protocol = "TCP"
      }
    }

    # Allow ingress from cloudflared (if enabled)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "cloudflared"
          }
        }
      }
      ports {
        port     = "5173"
        protocol = "TCP"
      }
    }

    # Allow egress to API service
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "api"
          }
        }
      }
      ports {
        port     = "4000"
        protocol = "TCP"
      }
    }

    # Allow egress to ElectricSQL (for SSR)
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "electric"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow egress to database (for SSR queries)
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Database Network Policy (PostgreSQL)
# =============================================================================
# Database needs:
#   Ingress: from API, web, electric, adminer, db-migrate job
#   Egress: none (database doesn't initiate connections)

resource "kubernetes_network_policy" "database_policy" {
  metadata {
    name      = "database-network-policy"
    namespace = var.namespace

    labels = {
      app        = "postgres"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "postgres"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from API service
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "api"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow ingress from web service (for SSR)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "web"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow ingress from ElectricSQL
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "electric"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow ingress from Adminer (for admin access)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "adminer"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow ingress from db-migrate job
    ingress {
      from {
        pod_selector {
          match_labels = {
            job = "db-migrate"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Database doesn't initiate outbound connections
    # No egress rules defined (implicitly denied by default policy)
  }
}

# =============================================================================
# ElectricSQL Network Policy
# =============================================================================
# ElectricSQL needs:
#   Ingress: from ingress-nginx, API service, web service, cloudflared
#   Egress: to database only

resource "kubernetes_network_policy" "electric_policy" {
  metadata {
    name      = "electric-network-policy"
    namespace = var.namespace

    labels = {
      app        = "electric"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "electric"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from ingress-nginx controller
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow ingress from API service
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "api"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow ingress from web service
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "web"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow ingress from cloudflared (if enabled)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "cloudflared"
          }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }

    # Allow egress to database
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Adminer Network Policy
# =============================================================================
# Adminer (database admin UI) needs:
#   Ingress: from ingress-nginx (when exposed), cloudflared
#   Egress: to database only
#
# Note: Adminer is removed from public ingress for security.
# Access via: kubectl port-forward -n plue svc/adminer 8080:8080

resource "kubernetes_network_policy" "adminer_policy" {
  metadata {
    name      = "adminer-network-policy"
    namespace = var.namespace

    labels = {
      app        = "adminer"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "adminer"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from ingress-nginx (if exposed)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    # Allow ingress from cloudflared (if enabled)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "cloudflared"
          }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    # Allow egress to database
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Cloudflared Network Policy
# =============================================================================
# Cloudflared tunnel daemon needs:
#   Ingress: none (only initiates outbound connections)
#   Egress: to ingress-nginx, external (Cloudflare edge)

resource "kubernetes_network_policy" "cloudflared_policy" {
  count = var.enable_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared-network-policy"
    namespace = var.namespace

    labels = {
      app        = "cloudflared"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Cloudflared doesn't receive ingress (it's a tunnel client)
    # No ingress rules (implicitly denied)

    # Allow egress to ingress-nginx
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
      ports {
        port     = "80"
        protocol = "TCP"
      }
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }

    # Allow egress to Cloudflare edge network
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
          ]
        }
      }
      ports {
        port     = "443"
        protocol = "TCP"
      }
      ports {
        port     = "7844"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Database Migration Job Network Policy
# =============================================================================
# db-migrate job needs:
#   Ingress: none
#   Egress: to database only

resource "kubernetes_network_policy" "db_migrate_policy" {
  metadata {
    name      = "db-migrate-network-policy"
    namespace = var.namespace

    labels = {
      job        = "db-migrate"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        job = "db-migrate"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # No ingress needed for migration job

    # Allow egress to database
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# =============================================================================
# Ingress Controller Communication
# =============================================================================
# Allow ingress-nginx to communicate with services in this namespace.
# This policy is applied in the plue namespace to allow cross-namespace access.

resource "kubernetes_network_policy" "allow_ingress_nginx" {
  metadata {
    name      = "allow-ingress-nginx"
    namespace = var.namespace

    labels = {
      app        = "plue"
      managed-by = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        # Apply to all pods that receive traffic from ingress
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }
    }
  }
}
