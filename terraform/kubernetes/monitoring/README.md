# Monitoring Infrastructure

Prometheus, AlertManager, and Grafana stack for comprehensive monitoring of the Plue platform.

## Components

### Prometheus
- **Purpose**: Metrics collection and storage
- **Port**: 9090
- **Retention**: 30 days (configurable)
- **Storage**: 50Gi persistent volume

**Scrape Targets**:
- Kubernetes API server
- Kubernetes nodes
- All pods with `prometheus.io/scrape: "true"` annotation
- API service (port 4000, /metrics)
- Web service (port 5173, /metrics)
- Electric service (port 3000, /metrics)

### AlertManager
- **Purpose**: Alert routing and notification management
- **Port**: 9093 (HTTP), 9094 (cluster)
- **Storage**: EmptyDir (ephemeral)

**Notification Channels** (configured as placeholders):
- Slack (for critical and warning alerts)
- PagerDuty (for critical alerts)
- Webhook (default)

### Grafana
- **Purpose**: Metrics visualization and dashboards
- **Port**: 3000
- **Storage**: 10Gi persistent volume
- **Default User**: admin
- **Default Password**: Set via `grafana_admin_password` variable

**Pre-configured Dashboards**:
1. **Plue - System Overview**: High-level infrastructure metrics
2. **Kubernetes Cluster**: Cluster resource usage and health
3. **API Performance**: API-specific performance metrics

## Alert Rules

### Pod Health
- `PodCrashLooping`: Pod restarting frequently
- `PodNotReady`: Pod not in Running/Succeeded state for >10 minutes
- `PodFrequentRestarts`: Pod restarted >5 times in 1 hour

### Resource Utilization
- `HighCPUUsage`: CPU usage >80% for 10 minutes (warning)
- `HighMemoryUsage`: Memory usage >80% for 10 minutes (warning)
- `CriticalCPUUsage`: CPU usage >95% for 5 minutes (critical)
- `CriticalMemoryUsage`: Memory usage >95% for 5 minutes (critical)

### Application Health
- `ServiceDown`: Service unavailable for >2 minutes
- `HighErrorRate`: 5xx error rate >1% for 5 minutes
- `CriticalErrorRate`: 5xx error rate >5% for 2 minutes
- `SlowResponseTime`: p99 response time >2s for 10 minutes

### Database
- `DatabaseConnectionFailure`: DB connection errors detected
- `HighDatabaseConnections`: >80% of max connections in use

### Storage
- `PersistentVolumeSpaceLow`: PV >80% full (warning)
- `PersistentVolumeSpaceCritical`: PV >90% full (critical)

### Certificates
- `CertificateExpiringSoon`: Certificate expires in <30 days (warning)
- `CertificateExpiryCritical`: Certificate expires in <7 days (critical)

### Deployments
- `DeploymentReplicasMismatch`: Available replicas != desired replicas
- `DeploymentGenerationMismatch`: Deployment rollout incomplete

### Nodes
- `NodeNotReady`: Node in NotReady state for >5 minutes
- `NodeMemoryPressure`: Node experiencing memory pressure
- `NodeDiskPressure`: Node experiencing disk pressure

## Usage

### Deploy Monitoring Stack

```bash
# From terraform/kubernetes directory
terraform init
terraform plan
terraform apply
```

### Access Grafana

```bash
# Port-forward locally
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Then open http://localhost:3000
# Username: admin
# Password: <grafana_admin_password from variables>
```

### Access Prometheus

```bash
# Port-forward locally
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Then open http://localhost:9090
```

### Access AlertManager

```bash
# Port-forward locally
kubectl port-forward -n monitoring svc/alertmanager 9093:9093

# Then open http://localhost:9093
```

### Configure Alert Notifications

To enable Slack or PagerDuty notifications, update `alertmanager.tf`:

**Slack Configuration**:
```hcl
# In alertmanager.tf receivers block
slack_configs = [{
  api_url       = var.alertmanager_slack_webhook
  channel       = "#alerts"
  title         = "{{ .GroupLabels.alertname }}"
  text          = "{{ .CommonAnnotations.summary }}\n{{ .CommonAnnotations.description }}"
  send_resolved = true
}]
```

**PagerDuty Configuration**:
```hcl
# In alertmanager.tf receivers block
pagerduty_configs = [{
  service_key   = var.alertmanager_pagerduty_key
  description   = "{{ .CommonAnnotations.summary }}"
  severity      = "{{ .CommonLabels.severity }}"
  send_resolved = true
}]
```

Then set the variables:
```bash
export TF_VAR_alertmanager_slack_webhook="https://hooks.slack.com/services/..."
export TF_VAR_alertmanager_pagerduty_key="your-pagerduty-key"
```

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `namespace` | Kubernetes namespace for monitoring | - | Yes |
| `prometheus_retention` | Prometheus data retention period | `"30d"` | No |
| `prometheus_storage_size` | Prometheus PV size | `"50Gi"` | No |
| `grafana_admin_password` | Grafana admin password | - | Yes |
| `alertmanager_slack_webhook` | Slack webhook URL | `""` | No |
| `alertmanager_pagerduty_key` | PagerDuty integration key | `""` | No |
| `domain` | Domain for Grafana ingress | - | Yes |
| `alert_cpu_threshold` | CPU usage alert threshold | `80` | No |
| `alert_memory_threshold` | Memory usage alert threshold | `80` | No |
| `alert_error_rate_threshold` | HTTP 5xx error rate threshold | `1` | No |

## Adding Custom Metrics

To expose metrics from your services:

1. **Add Prometheus annotations to your pod**:
```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "4000"
    prometheus.io/path: "/metrics"
```

2. **Expose metrics endpoint** in your service (e.g., `/metrics`)

3. **Use Prometheus client library** for your language:
   - Zig: No official client (implement custom HTTP endpoint)
   - TypeScript: `prom-client`
   - Go: `prometheus/client_golang`

## Troubleshooting

### Prometheus not scraping targets

```bash
# Check Prometheus config
kubectl get configmap -n monitoring prometheus-config -o yaml

# Check Prometheus logs
kubectl logs -n monitoring deployment/prometheus

# Verify service discovery
kubectl get endpoints -n plue
```

### Alerts not firing

```bash
# Check alert rules
kubectl get configmap -n monitoring prometheus-alerts -o yaml

# Check AlertManager config
kubectl get configmap -n monitoring alertmanager-config -o yaml

# Check AlertManager logs
kubectl logs -n monitoring deployment/alertmanager
```

### Grafana dashboards not loading

```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Verify datasource connection
# In Grafana UI: Configuration > Data Sources > Prometheus > Test
```

## Security Considerations

- All services run as non-root users
- Read-only root filesystems where possible
- Security contexts with seccomp profiles
- RBAC permissions scoped to monitoring namespace
- Sensitive values stored in Kubernetes secrets
- No external LoadBalancer (use port-forward or Ingress with auth)

## Maintenance

### Update Prometheus retention

```bash
# Edit variables.tf or override
terraform apply -var="prometheus_retention=60d"
```

### Increase storage size

```bash
# Edit variables.tf or override
terraform apply -var="prometheus_storage_size=100Gi"
```

### Add new alert rules

1. Edit `alerts.yaml`
2. Apply changes: `terraform apply`
3. Prometheus will automatically reload the configuration

### Backup Grafana dashboards

```bash
# Export all dashboards via API
kubectl port-forward -n monitoring svc/grafana 3000:3000
curl -u admin:password http://localhost:3000/api/search | jq -r '.[] | .uid' | \
  xargs -I {} curl -u admin:password http://localhost:3000/api/dashboards/uid/{} > dashboard-{}.json
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                  │
│                                                         │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐      │
│  │   API    │────▶│  Metrics │────▶│Prometheus│      │
│  │ Service  │     │ Endpoint │     │  :9090   │      │
│  └──────────┘     └──────────┘     └────┬─────┘      │
│                                          │             │
│  ┌──────────┐     ┌──────────┐          │             │
│  │   Web    │────▶│  Metrics │──────────┤             │
│  │ Service  │     │ Endpoint │          │             │
│  └──────────┘     └──────────┘          │             │
│                                          │             │
│  ┌──────────┐     ┌──────────┐          │             │
│  │ Electric │────▶│  Metrics │──────────┤             │
│  │ Service  │     │ Endpoint │          │             │
│  └──────────┘     └──────────┘          ▼             │
│                                    ┌──────────┐        │
│                                    │  Alert   │        │
│                                    │ Manager  │        │
│                                    │  :9093   │        │
│                                    └────┬─────┘        │
│                                         │              │
│                     ┌───────────────────┴────────┐    │
│                     ▼                            ▼     │
│              ┌────────────┐              ┌────────┐   │
│              │   Slack    │              │PagerDuty│   │
│              │  (Config)  │              │(Config)│   │
│              └────────────┘              └────────┘   │
│                                                        │
│  ┌──────────┐                                         │
│  │ Grafana  │◀────────── Prometheus                   │
│  │  :3000   │          (Data Source)                  │
│  └──────────┘                                         │
│                                                        │
└─────────────────────────────────────────────────────┘
```

## Next Steps

1. **Enable metrics endpoints** in API, Web, and Electric services
2. **Configure Slack/PagerDuty** notification channels
3. **Create custom dashboards** for business metrics
4. **Set up Ingress** with authentication for external access
5. **Configure backup** for Prometheus and Grafana data
6. **Add custom alert rules** for application-specific metrics
