# Infrastructure

Infrastructure configuration for Plue deployment across local, staging, and production environments.

## Overview

```
┌─────────────┐
│   Docker    │──→ Local development (docker-compose)
└─────────────┘
       │
       ├─────────────┐
       │    Helm     │──→ Kubernetes package manager
       └─────────────┘
              │
       ┌──────┴──────┐
       │      K8s    │──→ Raw manifests (RuntimeClass, PDBs, warm pool)
       └─────────────┘
              │
       ┌──────┴──────┐
       │  Terraform  │──→ GKE, networking, secrets, monitoring
       └─────────────┘
              │
       ┌──────┴──────┐
       │  Monitoring │──→ Prometheus, Grafana, Loki configs
       └─────────────┘
```

## Directories

| Directory | Purpose |
|-----------|---------|
| `docker/` | Local development with docker-compose |
| `helm/` | Kubernetes Helm chart for deployments |
| `k8s/` | Raw Kubernetes manifests (gVisor, PDBs, warm pool) |
| `terraform/` | Infrastructure as Code (GKE, VPC, IAM, secrets) |
| `monitoring/` | Observability stack (Prometheus, Grafana, Loki) |
| `scripts/` | Deployment automation and certificate generation |

## Deployment Targets

| Environment | Tool | Location |
|-------------|------|----------|
| Local | Docker Compose | `docker/docker-compose.yaml` |
| Staging | Helm + GKE | `scripts/deploy-staging.sh` |
| Production | Terraform + Helm | `terraform/environments/production/` |

## Quick Start

**Local development:**
```bash
cd docker
docker-compose up
```

**Staging deployment:**
```bash
./scripts/deploy-staging.sh
```

**Production (Terraform):**
```bash
cd terraform/environments/production
terraform apply
```

## Key Technologies

- **Container Runtime**: Docker + gVisor sandboxing
- **Orchestration**: Kubernetes (GKE)
- **IaC**: Terraform + Helm
- **Monitoring**: Prometheus, Grafana, Loki
- **Secrets**: External Secrets Operator (GCP Secret Manager)
- **CDN**: Cloudflare Workers (edge proxy)
- **Security**: mTLS, network policies, RBAC

## Architecture

```
                 ┌──────────────┐
                 │  Cloudflare  │ (Edge caching proxy)
                 └──────┬───────┘
                        │ mTLS
                 ┌──────▼───────┐
                 │   Ingress    │ (GKE Load Balancer)
                 └──────┬───────┘
            ┌───────────┼───────────┐
            │           │           │
       ┌────▼────┐ ┌────▼────┐ ┌───▼────┐
       │   Web   │ │   API   │ │ Runner │
       │ (Astro) │ │  (Zig)  │ │(Python)│
       └─────────┘ └────┬────┘ └────────┘
                        │
                   ┌────▼────┐
                   │ Postgres│
                   └─────────┘
```

## Security

- **gVisor**: Sandboxed runner execution
- **mTLS**: Authenticated origin pulls (Cloudflare → Origin)
- **Network Policies**: Restricted pod-to-pod communication
- **Secrets**: External Secrets Operator (never committed)
- **RBAC**: Fine-grained Kubernetes permissions

## Observability

Full monitoring stack integrated:

- **Metrics**: Prometheus (scrape targets: API, DB, runners)
- **Logs**: Loki + Promtail (aggregated container logs)
- **Dashboards**: Grafana (pre-configured for Plue services)
- **Alerts**: Prometheus AlertManager (configurable rules)

Access locally:
- Grafana: http://localhost:3001
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100

## See Also

- [Architecture Documentation](../architecture.md)
- [Infrastructure Details](../docs/infrastructure.md)
- [Terraform README](./terraform/README.md)
- [Monitoring README](./monitoring/README.md)
