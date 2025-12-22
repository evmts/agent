# Quick Start Guide - Monitoring Stack

Get Prometheus, AlertManager, and Grafana running in under 5 minutes.

## Prerequisites

- Kubernetes cluster running
- `kubectl` configured
- `terraform` >= 1.5.0

## 1. Deploy Monitoring Stack

```bash
cd terraform/kubernetes/monitoring

# Create configuration
cat > terraform.tfvars <<EOF
namespace              = "monitoring"
domain                 = "plue.dev"
grafana_admin_password = "$(openssl rand -base64 24)"
EOF

# Initialize and deploy
terraform init
terraform apply -auto-approve
```

## 2. Verify Deployment

```bash
# Check pods are running
kubectl get pods -n monitoring

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# prometheus-xxx                  1/1     Running   0          1m
# alertmanager-xxx                1/1     Running   0          1m
# grafana-xxx                     1/1     Running   0          1m
```

## 3. Access Services

### Grafana
```bash
# Port-forward
kubectl port-forward -n monitoring svc/grafana 3000:3000 &

# Open browser
open http://localhost:3000

# Login
# Username: admin
# Password: <check terraform.tfvars>
```

### Prometheus
```bash
# Port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

# Open browser
open http://localhost:9090

# Check targets
open http://localhost:9090/targets
```

### AlertManager
```bash
# Port-forward
kubectl port-forward -n monitoring svc/alertmanager 9093:9093 &

# Open browser
open http://localhost:9093
```

## 4. Enable Metrics in Your Services

Add Prometheus annotations to your deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
```

## 5. Configure Alerts (Optional)

### Slack Notifications

```bash
# Update terraform.tfvars
cat >> terraform.tfvars <<EOF
alertmanager_slack_webhook = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
EOF

# Edit alertmanager.tf (uncomment Slack config in receivers block)
# Then apply
terraform apply
```

### PagerDuty

```bash
# Update terraform.tfvars
cat >> terraform.tfvars <<EOF
alertmanager_pagerduty_key = "your-pagerduty-integration-key"
EOF

# Edit alertmanager.tf (uncomment PagerDuty config in receivers block)
# Then apply
terraform apply
```

## 6. Test Alerts

### Trigger a test alert

```bash
# Create a pod that crashes
kubectl run crash-test --image=busybox --restart=Always -- sh -c "exit 1"

# Wait 5 minutes, then check alerts
open http://localhost:9090/alerts

# Clean up
kubectl delete pod crash-test
```

## 7. Explore Dashboards

In Grafana (http://localhost:3000):

1. Go to "Dashboards" in the left menu
2. Open "Plue - System Overview" for infrastructure metrics
3. Open "Kubernetes Cluster" for node/pod metrics
4. Open "API Performance" for API-specific metrics

## Common Issues

### Prometheus not scraping targets

**Problem**: No data in Grafana

**Solution**:
```bash
# Check Prometheus targets
open http://localhost:9090/targets

# Check pod annotations
kubectl get pods -n plue -o yaml | grep -A 3 "annotations:"

# View Prometheus logs
kubectl logs -n monitoring deployment/prometheus
```

### Grafana can't connect to Prometheus

**Problem**: "Prometheus server not connected" error

**Solution**:
```bash
# Test connectivity from Grafana pod
kubectl exec -n monitoring deployment/grafana -- wget -qO- http://prometheus:9090/-/ready

# Check Grafana datasource config
kubectl get configmap -n monitoring grafana-datasources -o yaml
```

### Alerts not firing

**Problem**: No alerts showing up

**Solution**:
```bash
# Check alert rules are loaded
kubectl get configmap -n monitoring prometheus-alerts -o yaml

# Check Prometheus rules
open http://localhost:9090/rules

# Check AlertManager logs
kubectl logs -n monitoring deployment/alertmanager
```

## Clean Up

```bash
# Remove monitoring stack
cd terraform/kubernetes/monitoring
terraform destroy -auto-approve

# Remove namespace
kubectl delete namespace monitoring
```

## Next Steps

1. **Add metrics endpoints** to your services
2. **Configure Slack/PagerDuty** for notifications
3. **Create custom dashboards** for your metrics
4. **Set up Ingress** for external access
5. **Enable persistent storage backups**

## Resources

- Full documentation: [README.md](./README.md)
- Integration guide: [INTEGRATION.md](./INTEGRATION.md)
- Alert rules: [alerts.yaml](./alerts.yaml)

## Getting Help

```bash
# View Prometheus config
kubectl get configmap -n monitoring prometheus-config -o yaml

# View AlertManager config
kubectl get configmap -n monitoring alertmanager-config -o yaml

# View Grafana dashboards
kubectl get configmap -n monitoring grafana-dashboards -o yaml

# Check all monitoring resources
kubectl get all -n monitoring
```

---

**Total deployment time**: ~2-3 minutes

**Services deployed**: 3 (Prometheus, AlertManager, Grafana)

**Pre-configured dashboards**: 3

**Alert rules**: 22

**Storage used**: ~60Gi (50Gi Prometheus + 10Gi Grafana)
