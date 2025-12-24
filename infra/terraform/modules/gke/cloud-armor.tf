# Cloud Armor security policy for SSH
# Provides additional network-level DDoS protection for direct SSH access
#
# Note: This is optional but recommended when not using Cloudflare Spectrum
# for SSH termination. Provides:
# - Threat intelligence-based IP blocking
# - Rate limiting at the network level
# - ML-based DDoS protection (Adaptive Protection)

variable "enable_ssh_cloud_armor" {
  description = "Enable Cloud Armor protection for SSH endpoint"
  type        = bool
  default     = false
}

variable "ssh_rate_limit_threshold" {
  description = "Maximum SSH connections per IP per minute"
  type        = number
  default     = 100
}

variable "ssh_ban_duration_seconds" {
  description = "Duration in seconds to ban IPs that exceed rate limit"
  type        = number
  default     = 300
}

# Cloud Armor security policy for SSH protection
resource "google_compute_security_policy" "ssh_protection" {
  count = var.enable_ssh_cloud_armor ? 1 : 0

  name        = "${var.cluster_name}-ssh-protection"
  description = "SSH protection policy with rate limiting and threat intelligence"

  # Default rule - allow traffic
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Block known malicious IPs using Google's threat intelligence
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluateThreatIntelligence('iplist-known-malicious-ips')"
      }
    }
    description = "Block known malicious IPs from threat intelligence"
  }

  # Block Tor exit nodes (optional - uncomment if desired)
  # rule {
  #   action   = "deny(403)"
  #   priority = "1100"
  #   match {
  #     expr {
  #       expression = "evaluateThreatIntelligence('iplist-tor-exit-nodes')"
  #     }
  #   }
  #   description = "Block Tor exit nodes"
  # }

  # Block public cloud IPs (optional - uncomment if you want to block cloud providers)
  # rule {
  #   action   = "deny(403)"
  #   priority = "1200"
  #   match {
  #     expr {
  #       expression = "evaluateThreatIntelligence('iplist-public-clouds')"
  #     }
  #   }
  #   description = "Block public cloud provider IPs"
  # }

  # Rate limit rule - max connections per IP per minute
  rule {
    action   = "rate_based_ban"
    priority = "2000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.ssh_rate_limit_threshold
        interval_sec = 60
      }
      ban_duration_sec = var.ssh_ban_duration_seconds
    }
    description = "Rate limit SSH connections per IP"
  }

  # Enable adaptive protection (ML-based DDoS detection)
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }
}

# Backend service for SSH (if using external load balancer)
# This is only created if SSH Cloud Armor is enabled
resource "google_compute_backend_service" "ssh" {
  count = var.enable_ssh_cloud_armor ? 1 : 0

  name                  = "${var.cluster_name}-ssh-backend"
  protocol              = "TCP"
  port_name             = "ssh"
  timeout_sec           = 30
  security_policy       = google_compute_security_policy.ssh_protection[0].id
  load_balancing_scheme = "EXTERNAL"

  health_checks = [google_compute_health_check.ssh[0].id]

  backend {
    group           = google_container_node_pool.primary.instance_group_urls[0]
    balancing_mode  = "CONNECTION"
    max_connections = 1000
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Health check for SSH service
resource "google_compute_health_check" "ssh" {
  count = var.enable_ssh_cloud_armor ? 1 : 0

  name                = "${var.cluster_name}-ssh-health"
  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 2222
  }
}

# Output the security policy ID for reference
output "ssh_security_policy_id" {
  description = "ID of the Cloud Armor security policy for SSH"
  value       = var.enable_ssh_cloud_armor ? google_compute_security_policy.ssh_protection[0].id : null
}

output "ssh_security_policy_name" {
  description = "Name of the Cloud Armor security policy for SSH"
  value       = var.enable_ssh_cloud_armor ? google_compute_security_policy.ssh_protection[0].name : null
}
