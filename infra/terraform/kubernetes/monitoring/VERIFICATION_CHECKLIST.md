# Monitoring Stack Verification Checklist

Use this checklist to verify your monitoring infrastructure deployment.

## Pre-Deployment

- [ ] Kubernetes cluster is running and accessible
- [ ] `kubectl` is configured correctly
- [ ] Terraform >= 1.5.0 is installed
- [ ] `terraform.tfvars` file is created with required variables
- [ ] Grafana admin password is set (strong, secure password)

## Deployment

- [ ] `terraform init` completed successfully
- [ ] `terraform plan` shows expected resources (3 deployments, 3 services, etc.)
- [ ] `terraform apply` completed without errors
- [ ] No errors in terraform output

## Resource Verification

### Namespaces
```bash
kubectl get namespace monitoring
```
- [ ] Namespace `monitoring` exists

### Deployments
```bash
kubectl get deployments -n monitoring
```
- [ ] `prometheus` deployment exists (1/1 ready)
- [ ] `alertmanager` deployment exists (1/1 ready)
- [ ] `grafana` deployment exists (1/1 ready)

### Pods
```bash
kubectl get pods -n monitoring
```
- [ ] Prometheus pod is Running (1/1 ready)
- [ ] AlertManager pod is Running (1/1 ready)
- [ ] Grafana pod is Running (1/1 ready)
- [ ] No pods are in CrashLoopBackOff or Error state

### Services
```bash
kubectl get services -n monitoring
```
- [ ] `prometheus` service exists (ClusterIP, port 9090)
- [ ] `alertmanager` service exists (ClusterIP, ports 9093/9094)
- [ ] `grafana` service exists (ClusterIP, port 3000)

### ConfigMaps
```bash
kubectl get configmaps -n monitoring
```
- [ ] `prometheus-config` exists
- [ ] `prometheus-alerts` exists
- [ ] `alertmanager-config` exists
- [ ] `grafana-datasources` exists
- [ ] `grafana-dashboard-provider` exists
- [ ] `grafana-dashboards` exists

### Secrets
```bash
kubectl get secrets -n monitoring
```
- [ ] `grafana-admin` secret exists

### PersistentVolumeClaims
```bash
kubectl get pvc -n monitoring
```
- [ ] `prometheus-storage` PVC exists (Bound, 50Gi)
- [ ] `grafana-storage` PVC exists (Bound, 10Gi)

### RBAC
```bash
kubectl get clusterrole prometheus
kubectl get clusterrolebinding prometheus
```
- [ ] ClusterRole `prometheus` exists
- [ ] ClusterRoleBinding `prometheus` exists

## Functional Verification

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

- [ ] Prometheus UI accessible at http://localhost:9090
- [ ] Status > Targets page shows targets
- [ ] At least `prometheus` target is up
- [ ] Status > Configuration shows loaded config
- [ ] Status > Rules shows 22+ alert rules
- [ ] Graph page can query metrics (e.g., `up`)

**Key Checks**:
```bash
# Check targets
open http://localhost:9090/targets

# Check rules
open http://localhost:9090/rules

# Check alerts
open http://localhost:9090/alerts
```

- [ ] All expected targets are visible (may show "down" if services not yet configured)
- [ ] Alert rules are loaded and grouped by name
- [ ] No Prometheus errors in logs: `kubectl logs -n monitoring deployment/prometheus`

### AlertManager

```bash
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
```

- [ ] AlertManager UI accessible at http://localhost:9093
- [ ] Status page shows configuration
- [ ] Silence page is accessible
- [ ] No AlertManager errors in logs: `kubectl logs -n monitoring deployment/alertmanager`

### Grafana

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

- [ ] Grafana UI accessible at http://localhost:3000
- [ ] Can login with admin/<password>
- [ ] Prometheus datasource is configured (Configuration > Data Sources)
- [ ] Datasource test is successful (green "Data source is working")
- [ ] Three dashboards are visible (Dashboards > Browse):
  - [ ] Plue - System Overview
  - [ ] Kubernetes Cluster
  - [ ] API Performance
- [ ] Dashboards load without errors (may show "No data" if services not configured)
- [ ] No Grafana errors in logs: `kubectl logs -n monitoring deployment/grafana`

## Integration Verification

### Service Discovery

```bash
# Check Prometheus service discovery
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'
```

- [ ] Kubernetes API server target is discovered
- [ ] Kubernetes nodes are discovered
- [ ] Pods with annotations are discovered

### Metrics Collection

```bash
# Query Prometheus for collected metrics
kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=up' | jq .
```

- [ ] Query returns data
- [ ] At least `prometheus` job shows `up=1`

### Alert Rules Evaluation

```bash
# Check alert rules are being evaluated
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/rules | jq '.data.groups[] | {name, file}'
```

- [ ] Alert groups are loaded
- [ ] `alerts.yaml` file is referenced

### Grafana Datasource

In Grafana UI (http://localhost:3000):
1. Go to Configuration > Data Sources
2. Click on Prometheus datasource
3. Scroll down and click "Save & Test"

- [ ] Test returns success message: "Data source is working"

## Performance Verification

### Resource Usage

```bash
kubectl top pods -n monitoring
```

- [ ] Prometheus CPU usage is reasonable (<2000m)
- [ ] Prometheus memory usage is reasonable (<4Gi)
- [ ] AlertManager CPU usage is reasonable (<500m)
- [ ] AlertManager memory usage is reasonable (<512Mi)
- [ ] Grafana CPU usage is reasonable (<1000m)
- [ ] Grafana memory usage is reasonable (<1Gi)

### Storage Usage

```bash
kubectl exec -n monitoring deployment/prometheus -- df -h /prometheus
kubectl exec -n monitoring deployment/grafana -- df -h /var/lib/grafana
```

- [ ] Prometheus storage has available space
- [ ] Grafana storage has available space

## Security Verification

### Pod Security

```bash
kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}'
```

- [ ] All pods run as non-root
- [ ] Security contexts are properly configured
- [ ] Seccomp profiles are set

### RBAC Permissions

```bash
kubectl auth can-i list pods --as=system:serviceaccount:monitoring:prometheus --all-namespaces
```

- [ ] Prometheus service account has correct permissions
- [ ] No excessive permissions granted

### Secrets

```bash
kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
```

- [ ] Grafana password is set correctly
- [ ] Password is strong (not default)

## Alert Verification

### Trigger Test Alert

```bash
# Create a crashing pod
kubectl run crash-test --image=busybox --restart=Always -- sh -c "exit 1"

# Wait 5 minutes, then check
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts
```

- [ ] `PodCrashLooping` alert appears after 5 minutes
- [ ] Alert shows in AlertManager: http://localhost:9093
- [ ] Alert has correct labels (severity, component)

```bash
# Clean up
kubectl delete pod crash-test
```

- [ ] Alert resolves after pod is deleted

## Documentation Verification

- [ ] README.md exists and is comprehensive
- [ ] INTEGRATION.md provides clear integration steps
- [ ] QUICKSTART.md provides quick deployment guide
- [ ] DEPLOYMENT_SUMMARY.md documents all components
- [ ] All referenced files exist

## Troubleshooting Common Issues

### Issue: Prometheus targets showing as "down"

**Expected**: Normal if services don't have /metrics endpoints yet

**Fix**: Add metrics endpoints to services or verify annotations

### Issue: Grafana shows "No data"

**Expected**: Normal if Prometheus isn't scraping metrics yet

**Fix**: Configure service annotations and add /metrics endpoints

### Issue: Alerts not firing

**Check**:
```bash
kubectl logs -n monitoring deployment/prometheus | grep -i error
kubectl logs -n monitoring deployment/alertmanager | grep -i error
```

**Fix**: Review alert rule syntax in alerts.yaml

### Issue: PVC stuck in Pending

**Check**:
```bash
kubectl describe pvc -n monitoring prometheus-storage
```

**Fix**: Ensure storage class exists: `kubectl get storageclass`

## Post-Verification Steps

Once all checks pass:

- [ ] Document Grafana admin password in secure location
- [ ] Configure Slack/PagerDuty notification channels
- [ ] Add Prometheus annotations to application services
- [ ] Implement /metrics endpoints in services
- [ ] Set up Ingress for external access (optional)
- [ ] Configure backup strategy for persistent data
- [ ] Add custom alert rules for business metrics
- [ ] Create custom Grafana dashboards

## Sign-off

- [ ] All critical checks passed
- [ ] No errors in logs
- [ ] All pods are Running
- [ ] Services are accessible
- [ ] Documentation reviewed

**Verified by**: _______________

**Date**: _______________

**Notes**:
```


```

---

## Quick Verification Script

```bash
#!/bin/bash
# Save as verify-monitoring.sh

echo "Checking monitoring stack..."

# Namespace
kubectl get namespace monitoring &>/dev/null && echo "✅ Namespace exists" || echo "❌ Namespace missing"

# Pods
RUNNING=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l)
echo "✅ $RUNNING/3 pods running"

# Services
SERVICES=$(kubectl get svc -n monitoring --no-headers 2>/dev/null | wc -l)
echo "✅ $SERVICES/3 services created"

# PVCs
BOUND=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | grep Bound | wc -l)
echo "✅ $BOUND/2 PVCs bound"

# Port-forward test
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
PF_PID=$!
sleep 2
curl -s http://localhost:9090/-/ready &>/dev/null && echo "✅ Prometheus is ready" || echo "❌ Prometheus not ready"
kill $PF_PID 2>/dev/null

echo "Verification complete!"
```

**Usage**:
```bash
chmod +x verify-monitoring.sh
./verify-monitoring.sh
```
