# Helm

Kubernetes Helm chart for deploying Plue to GKE (staging and production).

## Chart Structure

```
plue/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
├── values-staging.yaml     # Staging overrides
├── values-production.yaml  # Production overrides
└── templates/              # K8s resource templates
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml
    ├── secrets.yaml
    ├── serviceaccount.yaml
    ├── hpa.yaml
    └── ...
```

## Installation

**Staging (per-engineer namespace):**
```bash
helm upgrade --install plue ./plue \
  --namespace $USER \
  --values plue/values-staging.yaml \
  --set image.tag=$(git rev-parse --short HEAD)
```

**Production:**
```bash
helm upgrade --install plue ./plue \
  --namespace production \
  --values plue/values-production.yaml \
  --set image.tag=v1.2.3
```

## Configuration

Key values:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `gcr.io/plue-production` | Container registry |
| `image.tag` | `latest` | Image tag (SHA or version) |
| `replicaCount` | `2` | Number of pod replicas |
| `autoscaling.enabled` | `true` | Enable HPA |
| `autoscaling.minReplicas` | `2` | Min pods |
| `autoscaling.maxReplicas` | `10` | Max pods |
| `ingress.enabled` | `true` | Enable ingress |
| `ingress.host` | `plue.dev` | Domain name |
| `database.host` | `postgres` | Database host |
| `runner.enabled` | `true` | Deploy runner pool |
| `monitoring.enabled` | `true` | Enable Prometheus metrics |

## Values Files

**values.yaml** (defaults for all environments):
- Base configuration
- Resource requests/limits
- Probe definitions
- Security contexts

**values-staging.yaml**:
- Smaller resource limits
- Relaxed autoscaling
- Staging domain (staging.plue.dev)
- Development-friendly settings

**values-production.yaml**:
- Production resource allocations
- Strict autoscaling rules
- Production domain (plue.dev)
- Security hardening

## Secrets

Secrets are managed via External Secrets Operator (not stored in chart):

```yaml
# Secrets automatically populated from GCP Secret Manager
- ANTHROPIC_API_KEY
- JWT_SECRET
- DATABASE_URL
- CLOUDFLARE_API_TOKEN
```

See `infra/k8s/external-secrets/` for configuration.

## Deployment Workflow

1. Build and push container images
2. Update image tag in values file
3. Run helm upgrade
4. Helm performs rolling update
5. Health checks ensure zero downtime

**Automated via CI/CD:**
```bash
# scripts/deploy-staging.sh handles:
- docker build + push
- helm upgrade with git SHA tag
- kubectl wait for rollout
```

## Monitoring

Chart includes:
- ServiceMonitor for Prometheus scraping
- Grafana dashboard ConfigMaps
- PodMonitor for runner metrics

Access via Grafana dashboards (deployed separately in monitoring stack).

## Resource Management

**Production defaults:**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**HPA scaling:**
- Target CPU: 70%
- Target Memory: 80%
- Scale up: 2 pods at a time
- Scale down: 1 pod every 5 minutes

## Network Policies

Chart includes NetworkPolicy resources:
- API can connect to Postgres
- Runner can connect to API (mTLS)
- Web can connect to API
- Default deny all other traffic

## gVisor Sandbox

Runner pods use gVisor RuntimeClass for security:
```yaml
runtimeClassName: gvisor
```

Configured in `infra/k8s/gvisor-runtimeclass.yaml`.

## Warm Runner Pool

Pre-warmed runner pods for fast workflow execution:
```yaml
runner:
  warmPool:
    enabled: true
    size: 5
    preloadImages: true
```

See `infra/k8s/warm-pool.yaml` for CronJob configuration.

## Rollback

Rollback to previous release:
```bash
helm rollback plue -n production
```

List releases:
```bash
helm history plue -n production
```

## Uninstall

```bash
helm uninstall plue -n production
```

Note: This does NOT delete PVCs (persistent volume claims). Delete manually if needed.
