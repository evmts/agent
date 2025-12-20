# Monitoring Module Integration Guide

This guide shows how to integrate the monitoring module into your Terraform configuration.

## Option 1: Standalone Deployment (Recommended for testing)

Deploy the monitoring stack independently:

```bash
cd terraform/kubernetes/monitoring

# Initialize
terraform init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
namespace               = "monitoring"
domain                  = "plue.dev"
grafana_admin_password  = "your-secure-password-here"

# Optional: Configure notifications
# alertmanager_slack_webhook   = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
# alertmanager_pagerduty_key   = "your-pagerduty-key"
EOF

# Deploy
terraform plan
terraform apply
```

## Option 2: Integrated Deployment (Production)

Add the monitoring module to your root module (e.g., `terraform/environments/production/main.tf`):

```hcl
# -----------------------------------------------------------------------------
# Module: Monitoring
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "../../kubernetes/monitoring"

  namespace              = "monitoring"
  domain                 = var.domain
  grafana_admin_password = var.grafana_admin_password

  # Optional: Alert notification channels
  alertmanager_slack_webhook  = var.alertmanager_slack_webhook
  alertmanager_pagerduty_key  = var.alertmanager_pagerduty_key

  # Optional: Customize thresholds
  alert_cpu_threshold         = 80
  alert_memory_threshold      = 80
  alert_error_rate_threshold  = 1

  # Optional: Customize storage
  prometheus_retention        = "30d"
  prometheus_storage_size     = "50Gi"

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.kubernetes]
}
```

Add variables to `terraform/environments/production/variables.tf`:

```hcl
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "alertmanager_slack_webhook" {
  description = "Slack webhook URL for alerts (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alertmanager_pagerduty_key" {
  description = "PagerDuty integration key (optional)"
  type        = string
  sensitive   = true
  default     = ""
}
```

Add to `terraform/environments/production/terraform.tfvars`:

```hcl
grafana_admin_password = "your-secure-password"
```

## Configure Kubernetes Services for Metrics

To expose metrics from your services, update the deployment manifests:

### API Service Example

```hcl
# In terraform/kubernetes/services/api.tf
resource "kubernetes_deployment" "api" {
  # ... existing config ...

  spec {
    template {
      metadata {
        labels = {
          app = "api"
        }
        # Add Prometheus annotations
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "4000"
          "prometheus.io/path"   = "/metrics"
        }
      }
      # ... rest of spec ...
    }
  }
}
```

### Web Service Example

```hcl
# In terraform/kubernetes/services/web.tf
resource "kubernetes_deployment" "web" {
  # ... existing config ...

  spec {
    template {
      metadata {
        labels = {
          app = "web"
        }
        # Add Prometheus annotations
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "5173"
          "prometheus.io/path"   = "/metrics"
        }
      }
      # ... rest of spec ...
    }
  }
}
```

### Electric Service Example

```hcl
# In terraform/kubernetes/services/electric.tf
resource "kubernetes_deployment" "electric" {
  # ... existing config ...

  spec {
    template {
      metadata {
        labels = {
          app = "electric"
        }
        # Add Prometheus annotations
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3000"
          "prometheus.io/path"   = "/metrics"
        }
      }
      # ... rest of spec ...
    }
  }
}
```

## Add Grafana Ingress (Optional)

If you want to expose Grafana externally, add an ingress rule to `terraform/kubernetes/ingress.tf`:

```hcl
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "monitoring"

    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/ssl-redirect"         = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect"   = "true"
      # Optional: Add basic auth for extra security
      "nginx.ingress.kubernetes.io/auth-type"            = "basic"
      "nginx.ingress.kubernetes.io/auth-secret"          = "grafana-basic-auth"
      "nginx.ingress.kubernetes.io/auth-realm"           = "Authentication Required"
    }

    labels = {
      app        = "grafana"
      managed-by = "terraform"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts = ["grafana.${var.domain}"]
      secret_name = "grafana-tls"
    }

    rule {
      host = "grafana.${var.domain}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "grafana"
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}

# Create basic auth secret
resource "kubernetes_secret" "grafana_basic_auth" {
  metadata {
    name      = "grafana-basic-auth"
    namespace = "monitoring"
  }

  data = {
    # htpasswd format: admin:$apr1$encrypted$password
    # Generate with: htpasswd -nb admin yourpassword
    auth = "admin:$apr1$..."
  }

  type = "Opaque"
}
```

## Deployment Order

When deploying with the integrated approach:

```bash
cd terraform/environments/production

# 1. Deploy infrastructure first
terraform apply -target=module.project
terraform apply -target=module.networking
terraform apply -target=module.cloudsql
terraform apply -target=module.gke

# 2. Deploy application services
terraform apply -target=module.kubernetes

# 3. Deploy monitoring (after services are running)
terraform apply -target=module.monitoring

# 4. Verify deployment
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

## Post-Deployment Steps

1. **Access Grafana**:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:3000
   # Open http://localhost:3000
   # Username: admin
   # Password: <your-grafana_admin_password>
   ```

2. **Verify Prometheus targets**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open http://localhost:9090/targets
   # Verify all services are being scraped
   ```

3. **Check AlertManager**:
   ```bash
   kubectl port-forward -n monitoring svc/alertmanager 9093:9093
   # Open http://localhost:9093
   ```

4. **Configure notifications** (if not set via Terraform):
   - Edit `alertmanager.tf` to uncomment Slack/PagerDuty configs
   - Run `terraform apply` to update

5. **Add custom dashboards**:
   - Log into Grafana
   - Create/import dashboards
   - Export JSON and add to `grafana.tf` ConfigMap

## Troubleshooting

### Prometheus not scraping services

```bash
# Check if services have metrics endpoints
kubectl exec -n plue deployment/api -- curl localhost:4000/metrics

# Check Prometheus logs
kubectl logs -n monitoring deployment/prometheus

# Check Prometheus config
kubectl get configmap -n monitoring prometheus-config -o yaml
```

### Grafana can't connect to Prometheus

```bash
# Verify Prometheus service is running
kubectl get svc -n monitoring prometheus

# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Test connectivity from Grafana pod
kubectl exec -n monitoring deployment/grafana -- wget -O- http://prometheus:9090/-/ready
```

### Alerts not firing

```bash
# Check alert rules are loaded
kubectl get configmap -n monitoring prometheus-alerts -o yaml

# Check Prometheus alerts page
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts

# Check AlertManager logs
kubectl logs -n monitoring deployment/alertmanager
```

## Security Best Practices

1. **Use strong passwords**:
   ```bash
   # Generate secure password
   openssl rand -base64 32
   ```

2. **Enable HTTPS** for external access via Ingress

3. **Restrict access** using NetworkPolicies:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: monitoring-network-policy
     namespace: monitoring
   spec:
     podSelector:
       matchLabels:
         app: grafana
     policyTypes:
       - Ingress
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 name: ingress-nginx
   ```

4. **Rotate secrets regularly**

5. **Enable audit logging** in Grafana

## Maintenance

### Upgrade Prometheus

```hcl
# In prometheus.tf, update image version
image = "prom/prometheus:v2.49.0"  # New version
```

### Expand storage

```bash
# Edit PVC (requires recreation)
terraform apply -var="prometheus_storage_size=100Gi"

# Or manually expand if storage class supports it
kubectl patch pvc -n monitoring prometheus-storage -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### Backup dashboards

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Export all dashboards
for uid in $(curl -s -u admin:password http://localhost:3000/api/search | jq -r '.[].uid'); do
  curl -s -u admin:password "http://localhost:3000/api/dashboards/uid/$uid" | \
    jq '.dashboard' > "dashboard-$uid.json"
done
```

## Next Steps

1. Implement `/metrics` endpoints in your services
2. Configure alert notification channels
3. Create custom dashboards for business metrics
4. Set up automated backups
5. Configure log aggregation (ELK/Loki)
6. Add distributed tracing (Jaeger/Tempo)
