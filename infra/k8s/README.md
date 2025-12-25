# Kubernetes

Raw Kubernetes manifests for resources not managed by Helm chart.

## Overview

These manifests configure cluster-level resources that apply across namespaces or require manual deployment before Helm charts.

## Files

| File | Purpose |
|------|---------|
| `gvisor-runtimeclass.yaml` | RuntimeClass for gVisor sandboxed runner pods |
| `network-policy.yaml` | Network isolation rules (pod-to-pod traffic) |
| `pod-disruption-budgets.yaml` | PDBs to ensure availability during node drain |
| `pod-template.yaml` | Template for runner pod creation |
| `warm-pool.yaml` | CronJob to maintain pre-warmed runner pods |
| `secrets.yaml` | Placeholder for manual secrets (use External Secrets) |
| `external-secrets/` | External Secrets Operator configuration |

## Deployment Order

1. **RuntimeClass** (gVisor)
2. **External Secrets Operator** (secrets management)
3. **Network Policies** (after namespaces exist)
4. **Pod Disruption Budgets** (after deployments exist)
5. **Warm Pool** (after API is deployed)

## gVisor RuntimeClass

Configures gVisor (runsc) as the container runtime for sandboxed execution:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

Runner pods specify:
```yaml
spec:
  runtimeClassName: gvisor
```

**Benefits:**
- Additional layer of isolation (syscall filtering)
- Protects host kernel from malicious code
- Required for untrusted workflow execution

**Installation:**
```bash
kubectl apply -f gvisor-runtimeclass.yaml
```

## Network Policies

Restricts pod-to-pod communication:

```
┌─────────┐
│   Web   │──→ API (port 4000)
└─────────┘
     ✗
┌─────────┐
│ Runner  │──→ API (port 4000, mTLS)
└─────────┘    ├─→ Postgres (port 5432)
               └─→ External (egress allowed)
```

Default policy: DENY all ingress/egress, then allow specific routes.

**Apply:**
```bash
kubectl apply -f network-policy.yaml -n production
```

## Pod Disruption Budgets

Ensures minimum availability during voluntary disruptions (node drain, upgrade):

| Service | Min Available | Max Unavailable |
|---------|---------------|-----------------|
| API | 1 | N/A |
| Web | 1 | N/A |
| Runner Pool | N/A | 50% |

**Apply:**
```bash
kubectl apply -f pod-disruption-budgets.yaml -n production
```

## Warm Pool

CronJob that maintains pre-warmed runner pods for fast workflow execution:

- Runs every 5 minutes
- Ensures `N` runner pods are always ready
- Pods are pre-pulled with common images
- Reduces workflow start latency from ~30s to <5s

**Architecture:**
```
CronJob (every 5min)
    ├─→ Check active runner count
    ├─→ Create pods if below threshold
    └─→ Pre-pull images (voltaire, playwright, etc.)
```

**Configure pool size:**
```yaml
env:
  - name: WARM_POOL_SIZE
    value: "5"
```

**Deploy:**
```bash
kubectl apply -f warm-pool.yaml -n production
```

## Pod Template

Template used by API server to dynamically create runner pods for workflow execution:

```yaml
apiVersion: v1
kind: Pod
metadata:
  generateName: runner-
spec:
  runtimeClassName: gvisor
  containers:
    - name: runner
      image: gcr.io/plue-production/runner:latest
      # Resource limits, env vars, volumes...
```

API server uses this template + workflow-specific overrides to spawn runners on-demand.

## Secrets

**DO NOT use `secrets.yaml` for production secrets.**

Use External Secrets Operator instead (see `external-secrets/README.md`).

The `secrets.yaml` file is a placeholder for local/testing use only.

## External Secrets

See dedicated directory:
```bash
cd external-secrets
cat README.md
```

Manages secrets from GCP Secret Manager via Kubernetes CRDs.

## Apply All

**Cluster-wide resources:**
```bash
kubectl apply -f gvisor-runtimeclass.yaml
```

**Namespace-specific resources:**
```bash
kubectl apply -f network-policy.yaml -n production
kubectl apply -f pod-disruption-budgets.yaml -n production
kubectl apply -f warm-pool.yaml -n production
```

## Monitoring

Check warm pool status:
```bash
kubectl get pods -n production -l app=runner-warm-pool
kubectl logs -n production -l app=warm-pool-cron
```

Check network policies:
```bash
kubectl get networkpolicies -n production
kubectl describe networkpolicy plue-api -n production
```

Check PDBs:
```bash
kubectl get pdb -n production
```

## Troubleshooting

**gVisor not working:**
- Verify GKE cluster has gVisor enabled
- Check node pool has `gvisor` sandbox configured
- Test with: `kubectl run test --image=alpine --rm -it --restart=Never --overrides='{"spec":{"runtimeClassName":"gvisor"}}' -- uname -a`

**Network policy blocking traffic:**
- Check policy matches pod labels
- Verify namespace labels for namespace selectors
- Test with: `kubectl exec -it <pod> -- nc -zv <target> <port>`

**Warm pool not creating pods:**
- Check CronJob logs: `kubectl logs -l app=warm-pool-cron`
- Verify ServiceAccount has permissions
- Check API server can list/create pods
