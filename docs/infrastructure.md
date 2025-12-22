# Plue Infrastructure

This document describes the development, staging, and production infrastructure for Plue, including local development setup, per-engineer staging environments, and production deployment.

## Table of Contents

1. [Overview](#overview)
2. [Environment Strategy](#environment-strategy)
3. [Local Development](#local-development)
4. [Staging Environments](#staging-environments)
5. [Production Environment](#production-environment)
6. [Terraform Structure](#terraform-structure)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Secrets Management](#secrets-management)
9. [Monitoring & Observability](#monitoring--observability)
10. [Runbooks](#runbooks)

---

## Overview

### Environment Tiers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ENVIRONMENTS                                   │
│                                                                          │
│   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐       │
│   │     LOCAL       │   │    STAGING      │   │   PRODUCTION    │       │
│   │                 │   │                 │   │                 │       │
│   │  Docker Compose │   │  GKE + gVisor   │   │  GKE + gVisor   │       │
│   │  In-process     │   │  Per-engineer   │   │  Full HA        │       │
│   │  No sandbox     │   │  Full sandbox   │   │  Auto-scaling   │       │
│   │                 │   │                 │   │                 │       │
│   │  Fast iteration │   │  High fidelity  │   │  Real users     │       │
│   └─────────────────┘   └─────────────────┘   └─────────────────┘       │
│                                                                          │
│   Fidelity:  Low            High                Highest                 │
│   Speed:     Fast           Medium              N/A                     │
│   Cost:      Free           ~$150/env/mo        ~$500/mo                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Infrastructure Components

| Component | Local | Staging | Production |
|-----------|-------|---------|------------|
| Zig API | Docker | GKE Pod | GKE Pod (HA) |
| Postgres | Docker | Cloud SQL | Cloud SQL (HA) |
| Runner | In-process | GKE Job + gVisor | GKE Job + gVisor |
| Warm Pool | None | 2 pods | 5+ pods (auto-scale) |
| CDN | None | Cloudflare | Cloudflare |
| Secrets | .env file | Secret Manager | Secret Manager |
| Monitoring | None | Basic | Full stack |

---

## Environment Strategy

### Per-Engineer Staging

Each engineer gets their own isolated staging environment:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GCP PROJECT: plue-staging                        │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    GKE Cluster: plue-staging                     │   │
│   │                                                                  │   │
│   │   ┌─────────────────────┐   ┌─────────────────────┐             │   │
│   │   │  Namespace: alice   │   │  Namespace: bob     │             │   │
│   │   │                     │   │                     │             │   │
│   │   │  - zig-api          │   │  - zig-api          │             │   │
│   │   │  - runner-pool      │   │  - runner-pool      │             │   │
│   │   │  - cloud-sql-proxy  │   │  - cloud-sql-proxy  │             │   │
│   │   │                     │   │                     │             │   │
│   │   │  alice.staging.     │   │  bob.staging.       │             │   │
│   │   │    plue.dev         │   │    plue.dev         │             │   │
│   │   └─────────────────────┘   └─────────────────────┘             │   │
│   │                                                                  │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │              Shared: Sandbox Node Pool                   │   │   │
│   │   │                     (gVisor enabled)                     │   │   │
│   │   └─────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Cloud SQL (shared)                            │   │
│   │                                                                  │   │
│   │   Database: plue_alice    Database: plue_bob                    │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Per-Engineer Staging?

1. **No conflicts** — Engineers can test breaking changes independently
2. **Full fidelity** — Real K8s, real gVisor, real Cloud SQL
3. **Fast feedback** — Deploy your branch, test immediately
4. **Cost efficient** — Shared cluster, separate namespaces

---

## Local Development

### Prerequisites

```bash
# Required
brew install docker
brew install zig       # 0.15.1+
brew install bun

# Optional
brew install jj        # For testing jj operations locally
```

### Quick Start

```bash
# Clone and setup
git clone https://github.com/plue/plue.git
cd plue

# Copy environment template
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY

# Start everything
make dev

# Or step by step:
docker-compose up -d postgres
zig build run          # Zig API on :4000
cd ui && bun dev       # UI on :3000
```

### Docker Compose Configuration

```yaml
# docker-compose.yaml
version: "3.8"

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: plue
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./db/schema.sql:/docker-entrypoint-initdb.d/01-schema.sql
      - ./db/seed.sql:/docker-entrypoint-initdb.d/02-seed.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Optional: Run Zig API in Docker (slower hot reload)
  zig-api:
    build:
      context: ./server
      dockerfile: Dockerfile.dev
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/plue
      RUNNER_MODE: in-process
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      LOG_LEVEL: debug
    volumes:
      - ./server/src:/app/src:ro
      - ./repos:/repos
    depends_on:
      postgres:
        condition: service_healthy
    profiles:
      - full  # Only start with: docker-compose --profile full up

volumes:
  postgres_data:
```

### Makefile

```makefile
# Makefile

.PHONY: dev dev-db dev-api dev-ui clean test

#──────────────────────────────────────────────────────────────────────────────
# Development
#──────────────────────────────────────────────────────────────────────────────

# Start everything (recommended)
dev: dev-db
	@echo "Starting Zig API and UI..."
	@trap 'kill 0' SIGINT; \
		zig build run & \
		(cd ui && bun dev) & \
		wait

# Just the database
dev-db:
	docker-compose up -d postgres
	@echo "Waiting for Postgres..."
	@until docker-compose exec -T postgres pg_isready; do sleep 1; done
	@echo "Postgres ready!"

# Just the API (assumes Postgres running)
dev-api:
	RUNNER_MODE=in-process zig build run

# Just the UI
dev-ui:
	cd ui && bun dev

# Full Docker environment
dev-docker:
	docker-compose --profile full up

#──────────────────────────────────────────────────────────────────────────────
# Testing
#──────────────────────────────────────────────────────────────────────────────

test:
	zig build test

test-e2e: dev-db
	cd e2e && bun playwright test

test-e2e-ui: dev-db
	cd e2e && bun playwright test --ui

#──────────────────────────────────────────────────────────────────────────────
# Staging Deployment
#──────────────────────────────────────────────────────────────────────────────

# Deploy to your staging environment
deploy-staging:
	@echo "Deploying to staging..."
	./scripts/deploy-staging.sh

# View your staging logs
logs-staging:
	kubectl logs -f -l app=zig-api -n $(USER)

#──────────────────────────────────────────────────────────────────────────────
# Cleanup
#──────────────────────────────────────────────────────────────────────────────

clean:
	docker-compose down -v
	rm -rf zig-out
	rm -rf ui/node_modules/.cache

# Nuclear option
clean-all: clean
	docker system prune -af
```

### Environment Variables

```bash
# .env.example

# Database (local)
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/plue

# Runner mode: 'in-process' for local, 'kubernetes' for staging/prod
RUNNER_MODE=in-process

# API Keys (required for agent features)
ANTHROPIC_API_KEY=sk-ant-...

# Optional: Your staging namespace (defaults to $USER)
STAGING_NAMESPACE=

# Optional: Enable debug logging
LOG_LEVEL=debug
```

### Local Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         LOCAL MACHINE                                    │
│                                                                          │
│   Terminal 1              Terminal 2              Terminal 3            │
│   ┌─────────────┐        ┌─────────────┐        ┌─────────────┐         │
│   │  Postgres   │        │   Zig API   │        │   Astro UI  │         │
│   │  (Docker)   │◄───────│   (native)  │◄───────│   (Bun)     │         │
│   │  :5432      │        │   :4000     │        │   :3000     │         │
│   └─────────────┘        └─────────────┘        └─────────────┘         │
│                                 │                      │                 │
│                                 │                      │                 │
│                          ┌──────┴──────┐               │                 │
│                          │  In-Process │               │                 │
│                          │   Runner    │               │                 │
│                          │ (no sandbox)│               │                 │
│                          └─────────────┘               │                 │
│                                                        │                 │
│   Browser: http://localhost:3000 ◄─────────────────────┘                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Staging Environments

### Deployment Script

```bash
#!/bin/bash
# scripts/deploy-staging.sh

set -euo pipefail

# Configuration
NAMESPACE="${STAGING_NAMESPACE:-$USER}"
PROJECT_ID="plue-staging"
CLUSTER="plue-staging"
REGION="us-central1"
REGISTRY="gcr.io/${PROJECT_ID}"

# Get current git info
GIT_SHA=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
IMAGE_TAG="${GIT_SHA}"

echo "══════════════════════════════════════════════════════════════"
echo "  Deploying to staging"
echo "  Namespace: ${NAMESPACE}"
echo "  Branch:    ${GIT_BRANCH}"
echo "  SHA:       ${GIT_SHA}"
echo "══════════════════════════════════════════════════════════════"

# Authenticate with GCP
echo "→ Authenticating with GCP..."
gcloud auth configure-docker gcr.io --quiet

# Build and push images
echo "→ Building images..."
docker build -t ${REGISTRY}/zig-api:${IMAGE_TAG} ./server
docker build -t ${REGISTRY}/runner:${IMAGE_TAG} ./runner

echo "→ Pushing images..."
docker push ${REGISTRY}/zig-api:${IMAGE_TAG}
docker push ${REGISTRY}/runner:${IMAGE_TAG}

# Get cluster credentials
echo "→ Getting cluster credentials..."
gcloud container clusters get-credentials ${CLUSTER} \
  --region ${REGION} \
  --project ${PROJECT_ID}

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Deploy with Helm
echo "→ Deploying with Helm..."
helm upgrade --install plue ./helm/plue \
  --namespace ${NAMESPACE} \
  --set image.repository=${REGISTRY}/zig-api \
  --set image.tag=${IMAGE_TAG} \
  --set runner.image.repository=${REGISTRY}/runner \
  --set runner.image.tag=${IMAGE_TAG} \
  --set ingress.host="${NAMESPACE}.staging.plue.dev" \
  --set database.name="plue_${NAMESPACE}" \
  --wait \
  --timeout 5m

# Wait for rollout
echo "→ Waiting for rollout..."
kubectl rollout status deployment/zig-api -n ${NAMESPACE} --timeout=5m

echo "══════════════════════════════════════════════════════════════"
echo "  ✓ Deployed successfully!"
echo "  URL: https://${NAMESPACE}.staging.plue.dev"
echo "══════════════════════════════════════════════════════════════"
```

### Helm Chart Structure

```
helm/plue/
├── Chart.yaml
├── values.yaml
├── values-staging.yaml
├── values-production.yaml
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── hpa.yaml
    ├── runner-deployment.yaml    # Warm pool
    ├── network-policy.yaml
    ├── service-account.yaml
    └── secrets.yaml
```

### Helm Values (Staging)

```yaml
# helm/plue/values-staging.yaml

replicaCount: 1

image:
  repository: gcr.io/plue-staging/zig-api
  pullPolicy: Always
  tag: "latest"

runner:
  image:
    repository: gcr.io/plue-staging/runner
    tag: "latest"

  warmPool:
    replicas: 2  # Small pool for staging

  resources:
    limits:
      cpu: "1"
      memory: "2Gi"
    requests:
      cpu: "250m"
      memory: "512Mi"

database:
  # Cloud SQL connection
  instanceConnectionName: "plue-staging:us-central1:plue-staging"
  name: "plue_${NAMESPACE}"  # Templated per-engineer

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  host: "${NAMESPACE}.staging.plue.dev"
  tls:
    enabled: true

resources:
  limits:
    cpu: "1"
    memory: "1Gi"
  requests:
    cpu: "250m"
    memory: "256Mi"

# Smaller for staging
autoscaling:
  enabled: false
```

### Staging Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GCP Project: plue-staging                             │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                         VPC Network                              │   │
│   │                                                                  │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │              GKE Cluster: plue-staging                   │   │   │
│   │   │                                                          │   │   │
│   │   │   ┌─────────────────────────────────────────────────┐   │   │   │
│   │   │   │            Default Node Pool (e2-medium)         │   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   │  ┌────────────────┐  ┌────────────────┐         │   │   │   │
│   │   │   │  │ ns: alice      │  │ ns: bob        │         │   │   │   │
│   │   │   │  │ ┌────────────┐ │  │ ┌────────────┐ │         │   │   │   │
│   │   │   │  │ │ zig-api    │ │  │ │ zig-api    │ │         │   │   │   │
│   │   │   │  │ └────────────┘ │  │ └────────────┘ │         │   │   │   │
│   │   │   │  │ ┌────────────┐ │  │ ┌────────────┐ │         │   │   │   │
│   │   │   │  │ │ sql-proxy  │ │  │ │ sql-proxy  │ │         │   │   │   │
│   │   │   │  │ └────────────┘ │  │ └────────────┘ │         │   │   │   │
│   │   │   │  └────────────────┘  └────────────────┘         │   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   └──────────────────────────────────────────────────┘   │   │   │
│   │   │                                                          │   │   │
│   │   │   ┌─────────────────────────────────────────────────┐   │   │   │
│   │   │   │         Sandbox Node Pool (gVisor, e2-standard-4)│   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   │   Shared by all namespaces                       │   │   │   │
│   │   │   │   ┌──────────┐ ┌──────────┐ ┌──────────┐        │   │   │   │
│   │   │   │   │ Standby  │ │ Standby  │ │ Standby  │        │   │   │   │
│   │   │   │   │ Runner   │ │ Runner   │ │ Runner   │        │   │   │   │
│   │   │   │   └──────────┘ └──────────┘ └──────────┘        │   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   └──────────────────────────────────────────────────┘   │   │   │
│   │   │                                                          │   │   │
│   │   └──────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │              Cloud SQL (PostgreSQL 16)                   │   │   │
│   │   │                                                          │   │   │
│   │   │   Databases: plue_alice, plue_bob                       │   │   │
│   │   │   Instance:  db-f1-micro (shared)                       │   │   │
│   │   │                                                          │   │   │
│   │   └─────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   DNS: *.staging.plue.dev → GKE Ingress                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Production Environment

### Production Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      GCP Project: plue-prod                              │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                        Cloudflare                                │   │
│   │                                                                  │   │
│   │   - CDN (git blobs, static assets)                              │   │
│   │   - DDoS protection                                              │   │
│   │   - SSL termination                                              │   │
│   │   - plue.dev → GKE                                              │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                      │
│                                   ▼                                      │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                      GKE Cluster: plue-prod                      │   │
│   │                        (Regional, HA)                            │   │
│   │                                                                  │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │              Default Node Pool                           │   │   │
│   │   │              (3x e2-standard-4, multi-zone)              │   │   │
│   │   │                                                          │   │   │
│   │   │   ┌─────────────────────────────────────────────────┐   │   │   │
│   │   │   │              Namespace: production               │   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   │   ┌──────────┐ ┌──────────┐ ┌──────────┐        │   │   │   │
│   │   │   │   │ zig-api  │ │ zig-api  │ │ zig-api  │        │   │   │   │
│   │   │   │   │ (zone-a) │ │ (zone-b) │ │ (zone-c) │        │   │   │   │
│   │   │   │   └──────────┘ └──────────┘ └──────────┘        │   │   │   │
│   │   │   │                                                  │   │   │   │
│   │   │   └──────────────────────────────────────────────────┘   │   │   │
│   │   │                                                          │   │   │
│   │   └──────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   │   ┌─────────────────────────────────────────────────────────┐   │   │
│   │   │              Sandbox Node Pool                           │   │   │
│   │   │              (gVisor, auto-scaling 2-20)                 │   │   │
│   │   │                                                          │   │   │
│   │   │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │   │   │
│   │   │   │ Standby  │ │ Standby  │ │ Standby  │ │ Standby  │   │   │   │
│   │   │   │ Runner 1 │ │ Runner 2 │ │ Runner 3 │ │ Runner 4 │   │   │   │
│   │   │   └──────────┘ └──────────┘ └──────────┘ └──────────┘   │   │   │
│   │   │         ... auto-scales to 20 ...                       │   │   │
│   │   │                                                          │   │   │
│   │   └──────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │              Cloud SQL (PostgreSQL 16)                           │   │
│   │              (db-custom-2-8192, HA, multi-zone)                 │   │
│   │                                                                  │   │
│   │   - Automated backups                                           │   │
│   │   - Point-in-time recovery                                      │   │
│   │   - Read replicas (optional)                                    │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │              Monitoring                                          │   │
│   │                                                                  │   │
│   │   - Cloud Monitoring (metrics)                                  │   │
│   │   - Cloud Logging (logs)                                        │   │
│   │   - Uptime checks                                               │   │
│   │   - PagerDuty integration                                       │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Terraform Structure

### Directory Layout

```
terraform/
├── modules/                      # Reusable modules
│   ├── gke-cluster/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── node-pools.tf
│   │
│   ├── cloud-sql/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── staging-namespace/        # Per-engineer staging resources
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── networking/
│   │   ├── main.tf
│   │   ├── vpc.tf
│   │   ├── subnets.tf
│   │   └── firewall.tf
│   │
│   └── dns/
│       ├── main.tf
│       └── cloudflare.tf
│
├── environments/
│   │
│   ├── staging-base/             # Shared staging infra (run once by admin)
│   │   ├── main.tf               # GKE cluster, Cloud SQL instance
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   │
│   ├── staging-alice/            # Alice's staging (run by Alice)
│   │   ├── main.tf               # Uses staging-namespace module
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   │
│   ├── staging-bob/              # Bob's staging (run by Bob)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   │
│   └── production/               # Production (run by CI/admin)
│       ├── main.tf
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── backend.tf
│
└── scripts/
    ├── init-staging-base.sh      # One-time setup by admin
    ├── init-my-staging.sh        # Run by each engineer
    └── init-production.sh
```

### Ownership Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        TERRAFORM OWNERSHIP                               │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    staging-base (Admin)                          │   │
│   │                                                                  │   │
│   │   Owner: Platform team / Admin                                  │   │
│   │   Contains: GKE cluster, Cloud SQL instance, VPC, shared infra  │   │
│   │   State: gs://plue-terraform/staging-base                       │   │
│   │   Deploys: Rarely (infra changes only)                          │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                      │
│                 ┌─────────────────┴─────────────────┐                   │
│                 │                                   │                   │
│                 ▼                                   ▼                   │
│   ┌───────────────────────────┐   ┌───────────────────────────┐        │
│   │   staging-alice (Alice)   │   │   staging-bob (Bob)       │        │
│   │                           │   │                           │        │
│   │   Owner: Alice            │   │   Owner: Bob              │        │
│   │   Contains:               │   │   Contains:               │        │
│   │   - K8s namespace         │   │   - K8s namespace         │        │
│   │   - Database (in shared   │   │   - Database (in shared   │        │
│   │     Cloud SQL)            │   │     Cloud SQL)            │        │
│   │   - Secrets               │   │   - Secrets               │        │
│   │   - Ingress               │   │   - Ingress               │        │
│   │                           │   │                           │        │
│   │   State: gs://plue-tf/    │   │   State: gs://plue-tf/    │        │
│   │          staging-alice    │   │          staging-bob      │        │
│   │                           │   │                           │        │
│   │   URL: alice.staging.     │   │   URL: bob.staging.       │        │
│   │        plue.dev           │   │        plue.dev           │        │
│   └───────────────────────────┘   └───────────────────────────┘        │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    production (CI/Admin)                         │   │
│   │                                                                  │   │
│   │   Owner: CI pipeline / Platform team                            │   │
│   │   Contains: Everything (separate GKE, Cloud SQL, etc.)          │   │
│   │   State: gs://plue-terraform/production                         │   │
│   │   Deploys: On merge to main                                     │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Module: GKE Cluster

```hcl
# terraform/modules/gke-cluster/main.tf

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "default_node_pool_config" {
  type = object({
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size_gb = number
  })
}

variable "sandbox_node_pool_config" {
  type = object({
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size_gb = number
  })
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# GKE Cluster
resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Use separately managed node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable GKE features
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Maintenance window (2 AM - 6 AM UTC on weekends)
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Release channel
  release_channel {
    channel = var.environment == "production" ? "STABLE" : "REGULAR"
  }

  resource_labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Default Node Pool (API, regular workloads)
resource "google_container_node_pool" "default" {
  name     = "default-pool"
  location = var.region
  cluster  = google_container_cluster.cluster.name
  project  = var.project_id

  autoscaling {
    min_node_count = var.default_node_pool_config.min_count
    max_node_count = var.default_node_pool_config.max_count
  }

  node_config {
    machine_type = var.default_node_pool_config.machine_type
    disk_size_gb = var.default_node_pool_config.disk_size_gb
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      pool = "default"
    }
  }
}

# Sandbox Node Pool (gVisor for runners)
resource "google_container_node_pool" "sandbox" {
  name     = "sandbox-pool"
  location = var.region
  cluster  = google_container_cluster.cluster.name
  project  = var.project_id

  autoscaling {
    min_node_count = var.sandbox_node_pool_config.min_count
    max_node_count = var.sandbox_node_pool_config.max_count
  }

  node_config {
    machine_type = var.sandbox_node_pool_config.machine_type
    disk_size_gb = var.sandbox_node_pool_config.disk_size_gb
    disk_type    = "pd-ssd"

    # Enable gVisor
    sandbox_config {
      sandbox_type = "gvisor"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Taint so only sandbox workloads schedule here
    taint {
      key    = "sandbox.gke.io/runtime"
      value  = "gvisor"
      effect = "NO_SCHEDULE"
    }

    labels = {
      pool = "sandbox"
    }
  }
}

# Outputs
output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}
```

### Module: Cloud SQL

```hcl
# terraform/modules/cloud-sql/main.tf

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tier" {
  type    = string
  default = "db-f1-micro"
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "databases" {
  type    = list(string)
  default = ["plue"]
}

resource "google_sql_database_instance" "instance" {
  name             = var.instance_name
  database_version = "POSTGRES_16"
  region           = var.region
  project          = var.project_id

  settings {
    tier              = var.tier
    availability_type = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_size         = var.environment == "production" ? 50 : 10
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.environment == "production"
      start_time                     = "03:00"

      backup_retention_settings {
        retained_backups = var.environment == "production" ? 30 : 7
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }

    insights_config {
      query_insights_enabled = var.environment == "production"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries > 1s
    }
  }

  deletion_protection = var.environment == "production"
}

# Create databases
resource "google_sql_database" "databases" {
  for_each = toset(var.databases)

  name     = each.value
  instance = google_sql_database_instance.instance.name
  project  = var.project_id
}

# Create user
resource "google_sql_user" "user" {
  name     = "plue"
  instance = google_sql_database_instance.instance.name
  project  = var.project_id
  password = random_password.db_password.result
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

# Store password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.instance_name}-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

output "instance_connection_name" {
  value = google_sql_database_instance.instance.connection_name
}

output "private_ip" {
  value = google_sql_database_instance.instance.private_ip_address
}
```

### Module: Staging Namespace (Per-Engineer)

```hcl
# terraform/modules/staging-namespace/main.tf

variable "engineer_name" {
  type        = string
  description = "Engineer's name (used for namespace, database, URL)"
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "sql_instance_name" {
  type = string
}

variable "domain" {
  type    = string
  default = "staging.plue.dev"
}

# Get cluster credentials
data "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# Create database in shared Cloud SQL instance
resource "google_sql_database" "database" {
  name     = "plue_${var.engineer_name}"
  instance = var.sql_instance_name
  project  = var.project_id
}

# Kubernetes provider configured from cluster data
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
  }
}

data "google_client_config" "default" {}

# Create namespace
resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.engineer_name

    labels = {
      environment = "staging"
      owner       = var.engineer_name
      managed_by  = "terraform"
    }
  }
}

# Create secrets in namespace
resource "kubernetes_secret" "plue_secrets" {
  metadata {
    name      = "plue-secrets"
    namespace = kubernetes_namespace.namespace.metadata[0].name
  }

  data = {
    ANTHROPIC_API_KEY = data.google_secret_manager_secret_version.anthropic_key.secret_data
    DATABASE_URL      = "postgresql://plue:${data.google_secret_manager_secret_version.db_password.secret_data}@localhost:5432/plue_${var.engineer_name}"
  }
}

data "google_secret_manager_secret_version" "anthropic_key" {
  secret  = "anthropic-api-key"
  project = var.project_id
}

data "google_secret_manager_secret_version" "db_password" {
  secret  = "plue-staging-db-password"
  project = var.project_id
}

# Deploy with Helm
resource "helm_release" "plue" {
  name      = "plue"
  namespace = kubernetes_namespace.namespace.metadata[0].name
  chart     = "${path.module}/../../../helm/plue"

  values = [
    file("${path.module}/../../../helm/plue/values-staging.yaml")
  ]

  set {
    name  = "ingress.host"
    value = "${var.engineer_name}.${var.domain}"
  }

  set {
    name  = "database.name"
    value = "plue_${var.engineer_name}"
  }

  set {
    name  = "engineer"
    value = var.engineer_name
  }
}

# DNS record
resource "cloudflare_record" "staging" {
  zone_id = var.cloudflare_zone_id
  name    = "${var.engineer_name}.staging"
  type    = "CNAME"
  value   = "staging.plue.dev"
  proxied = true
}

# Outputs
output "namespace" {
  value = kubernetes_namespace.namespace.metadata[0].name
}

output "url" {
  value = "https://${var.engineer_name}.${var.domain}"
}

output "database" {
  value = google_sql_database.database.name
}
```

### Environment: Staging Base (Admin-Owned)

```hcl
# terraform/environments/staging-base/main.tf
#
# This creates the SHARED staging infrastructure.
# Run once by admin. Engineers don't touch this.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "plue-terraform-state"
    prefix = "staging-base"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  environment = "staging"
}

# GKE Cluster (shared by all engineers)
module "gke" {
  source = "../../modules/gke-cluster"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "plue-staging"
  environment  = local.environment

  default_node_pool_config = {
    machine_type = "e2-medium"
    min_count    = 1
    max_count    = 3
    disk_size_gb = 50
  }

  sandbox_node_pool_config = {
    machine_type = "e2-standard-4"
    min_count    = 1
    max_count    = 5
    disk_size_gb = 50
  }
}

# Cloud SQL instance (shared, databases created per-engineer)
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id        = var.project_id
  region            = var.region
  instance_name     = "plue-staging"
  environment       = local.environment
  tier              = "db-f1-micro"
  high_availability = false
  vpc_id            = module.gke.vpc_id

  # No databases here - engineers create their own
  databases = []
}

# Shared secrets
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "anthropic-api-key"
  project   = var.project_id
  replication { auto {} }
}

# Outputs for engineers to reference
output "cluster_name" {
  value = module.gke.cluster_name
}

output "sql_instance_name" {
  value = module.cloud_sql.instance_name
}

output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}
```

### Environment: Per-Engineer Staging

```hcl
# terraform/environments/staging-alice/main.tf
#
# Alice's personal staging environment.
# Alice owns this and can deploy/destroy freely.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "gcs" {
    bucket = "plue-terraform-state"
    prefix = "staging-alice"  # Each engineer has their own state
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Reference outputs from staging-base
data "terraform_remote_state" "base" {
  backend = "gcs"
  config = {
    bucket = "plue-terraform-state"
    prefix = "staging-base"
  }
}

# Create my staging namespace and resources
module "my_staging" {
  source = "../../modules/staging-namespace"

  engineer_name     = "alice"  # ← Change this to your name
  project_id        = data.terraform_remote_state.base.outputs.project_id
  region            = data.terraform_remote_state.base.outputs.region
  cluster_name      = data.terraform_remote_state.base.outputs.cluster_name
  sql_instance_name = data.terraform_remote_state.base.outputs.sql_instance_name
  cloudflare_zone_id = var.cloudflare_zone_id
}

# Outputs
output "url" {
  value = module.my_staging.url
}

output "namespace" {
  value = module.my_staging.namespace
}

output "database" {
  value = module.my_staging.database
}
```

```hcl
# terraform/environments/staging-alice/terraform.tfvars

project_id         = "plue-staging"
region             = "us-central1"
cloudflare_zone_id = "your-zone-id"
```

### Engineer Workflow

```bash
#!/bin/bash
# scripts/init-my-staging.sh
#
# Run this to create your personal staging environment.
# Copy staging-alice to staging-<yourname> first!

set -euo pipefail

ENGINEER=${1:-$USER}
ENV_DIR="terraform/environments/staging-${ENGINEER}"

echo "═══════════════════════════════════════════════════════════════"
echo "  Setting up staging environment for: ${ENGINEER}"
echo "═══════════════════════════════════════════════════════════════"

# Check if directory exists
if [ ! -d "$ENV_DIR" ]; then
  echo "Creating environment directory..."
  cp -r terraform/environments/staging-alice "$ENV_DIR"

  # Update engineer name in main.tf
  sed -i '' "s/engineer_name.*=.*\"alice\"/engineer_name = \"${ENGINEER}\"/" "$ENV_DIR/main.tf"
  sed -i '' "s/staging-alice/staging-${ENGINEER}/" "$ENV_DIR/main.tf"

  echo "Created $ENV_DIR - please review and commit!"
fi

cd "$ENV_DIR"

# Initialize Terraform
echo "→ Initializing Terraform..."
terraform init

# Plan
echo "→ Planning..."
terraform plan -out=tfplan

# Confirm
read -p "Apply this plan? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  terraform apply tfplan

  echo "═══════════════════════════════════════════════════════════════"
  echo "  ✓ Staging environment ready!"
  echo "  URL: https://${ENGINEER}.staging.plue.dev"
  echo "  Namespace: ${ENGINEER}"
  echo "═══════════════════════════════════════════════════════════════"
fi
```

### Quick Commands for Engineers

```bash
# First time setup (creates your staging env)
./scripts/init-my-staging.sh

# Deploy latest code to your staging
cd terraform/environments/staging-$USER
terraform apply

# Destroy your staging (saves money when not using)
terraform destroy

# View your staging logs
kubectl logs -f -l app=zig-api -n $USER

# Port-forward to your staging database
kubectl port-forward svc/cloud-sql-proxy 5432:5432 -n $USER
```

### Environment: Production

```hcl
# terraform/environments/production/main.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "gcs" {
    bucket = "plue-terraform-state"
    prefix = "production"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  environment = "production"
}

# GKE Cluster
module "gke" {
  source = "../../modules/gke-cluster"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "plue-prod"
  environment  = local.environment

  default_node_pool_config = {
    machine_type = "e2-standard-4"
    min_count    = 3
    max_count    = 10
    disk_size_gb = 100
  }

  sandbox_node_pool_config = {
    machine_type = "e2-standard-4"
    min_count    = 2
    max_count    = 20
    disk_size_gb = 100
  }
}

# Cloud SQL (HA)
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id        = var.project_id
  region            = var.region
  instance_name     = "plue-prod"
  environment       = local.environment
  tier              = "db-custom-2-8192"
  high_availability = true
  vpc_id            = module.gke.vpc_id

  databases = ["plue"]
}

# Cloudflare DNS
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  type    = "A"
  value   = module.gke.ingress_ip
  proxied = true
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  value   = "plue.dev"
  proxied = true
}
```

```hcl
# terraform/environments/production/terraform.tfvars

project_id = "plue-prod"
region     = "us-central1"
```

---

## CI/CD Pipeline

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yaml
name: Deploy

on:
  push:
    branches:
      - main
      - 'staging/*'  # staging/alice, staging/bob

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true

env:
  PROJECT_ID_STAGING: plue-staging
  PROJECT_ID_PROD: plue-prod
  REGION: us-central1
  REGISTRY: gcr.io

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1

      - name: Run tests
        run: zig build test

  build:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Docker meta
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.PROJECT_ID_STAGING }}/zig-api
          tags: |
            type=sha,prefix=

      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Auth to GCP
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Configure Docker
        run: gcloud auth configure-docker gcr.io

      - name: Build and push API
        uses: docker/build-push-action@v5
        with:
          context: ./server
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build and push Runner
        uses: docker/build-push-action@v5
        with:
          context: ./runner
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.PROJECT_ID_STAGING }}/runner:${{ steps.meta.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    needs: build
    if: startsWith(github.ref, 'refs/heads/staging/')
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Get namespace from branch
        id: namespace
        run: |
          BRANCH=${GITHUB_REF#refs/heads/staging/}
          echo "namespace=$BRANCH" >> $GITHUB_OUTPUT

      - name: Auth to GCP
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Get GKE credentials
        uses: google-github-actions/get-gke-credentials@v2
        with:
          cluster_name: plue-staging
          location: ${{ env.REGION }}

      - name: Deploy to staging
        run: |
          helm upgrade --install plue ./helm/plue \
            --namespace ${{ steps.namespace.outputs.namespace }} \
            --create-namespace \
            --set image.tag=${{ needs.build.outputs.image_tag }} \
            --set ingress.host="${{ steps.namespace.outputs.namespace }}.staging.plue.dev" \
            -f helm/plue/values-staging.yaml \
            --wait

      - name: Run E2E tests
        run: |
          cd e2e
          PLUE_URL="https://${{ steps.namespace.outputs.namespace }}.staging.plue.dev" \
            bun playwright test

  deploy-production:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Auth to GCP
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_PROD_SA_KEY }}

      - name: Get GKE credentials
        uses: google-github-actions/get-gke-credentials@v2
        with:
          cluster_name: plue-prod
          location: ${{ env.REGION }}
          project_id: ${{ env.PROJECT_ID_PROD }}

      - name: Deploy to production
        run: |
          helm upgrade --install plue ./helm/plue \
            --namespace production \
            --set image.tag=${{ needs.build.outputs.image_tag }} \
            -f helm/plue/values-production.yaml \
            --wait

      - name: Smoke test
        run: |
          curl -f https://api.plue.dev/health
```

### Branch Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GIT BRANCHES                                    │
│                                                                          │
│   main ──────────────────────────────────────────────► production       │
│     │                                                                    │
│     ├── staging/alice ───────────────────────────────► alice.staging    │
│     │                                                                    │
│     └── staging/bob ─────────────────────────────────► bob.staging      │
│                                                                          │
│   Workflow:                                                              │
│   1. Create branch: staging/<your-name>                                 │
│   2. Push changes → auto-deploys to <your-name>.staging.plue.dev       │
│   3. Test in staging                                                     │
│   4. Merge to main → auto-deploys to production                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Secrets Management

### Secret Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     GCP Secret Manager                                   │
│                                                                          │
│   plue-staging/                                                          │
│   ├── anthropic-api-key                                                 │
│   ├── plue-staging-db-password                                          │
│   ├── github-app-private-key                                            │
│   └── cloudflare-api-token                                              │
│                                                                          │
│   plue-prod/                                                             │
│   ├── anthropic-api-key                                                 │
│   ├── plue-prod-db-password                                             │
│   ├── github-app-private-key                                            │
│   └── cloudflare-api-token                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### External Secrets Operator

```yaml
# k8s/external-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: plue-secrets
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcp-secrets
  target:
    name: plue-secrets
    creationPolicy: Owner
  data:
    - secretKey: ANTHROPIC_API_KEY
      remoteRef:
        key: anthropic-api-key
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: plue-prod-db-password
```

---

## Monitoring & Observability

### Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Metrics | Cloud Monitoring | Infrastructure + app metrics |
| Logs | Cloud Logging | Centralized logs |
| Traces | Cloud Trace | Distributed tracing |
| Uptime | Cloud Monitoring | Availability checks |
| Alerts | PagerDuty | On-call notifications |

### Key Metrics

```yaml
# Uptime check
resource "google_monitoring_uptime_check_config" "api" {
  display_name = "API Health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = "443"
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = "api.plue.dev"
    }
  }
}

# Alert policy
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Error rate > 5%"

    condition_threshold {
      filter          = "resource.type=\"k8s_container\" AND metric.type=\"logging.googleapis.com/log_entry_count\" AND metric.labels.severity=\"ERROR\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.pagerduty.id]
}
```

---

## Runbooks

### Adding a New Engineer

```bash
#!/bin/bash
# scripts/create-engineer-namespace.sh

ENGINEER=$1

if [ -z "$ENGINEER" ]; then
  echo "Usage: $0 <engineer-name>"
  exit 1
fi

# 1. Add to Terraform
echo "Adding $ENGINEER to terraform/environments/staging/main.tf..."
# Edit engineers list

# 2. Apply Terraform (creates database)
cd terraform/environments/staging
terraform apply

# 3. Create namespace
kubectl create namespace $ENGINEER

# 4. Setup secrets
kubectl create secret generic plue-secrets \
  --namespace $ENGINEER \
  --from-literal=ANTHROPIC_API_KEY=$(gcloud secrets versions access latest --secret=anthropic-api-key)

# 5. Create branch
git checkout -b staging/$ENGINEER
git push -u origin staging/$ENGINEER

echo "Done! $ENGINEER can now push to staging/$ENGINEER"
echo "URL: https://$ENGINEER.staging.plue.dev"
```

### Deploying Hotfix to Production

```bash
#!/bin/bash
# scripts/hotfix.sh

# 1. Create hotfix branch from main
git checkout main
git pull
git checkout -b hotfix/description

# 2. Make fix
# ... edit files ...

# 3. Test locally
make test

# 4. Push directly to main (skips staging)
git checkout main
git merge hotfix/description
git push origin main

# 5. Monitor deployment
kubectl rollout status deployment/zig-api -n production
```

### Rolling Back Production

```bash
#!/bin/bash
# scripts/rollback.sh

# List recent releases
helm history plue -n production

# Rollback to previous
helm rollback plue -n production

# Or to specific revision
helm rollback plue 5 -n production
```

### Scaling Warm Pool

```bash
# Increase warm pool (during expected high traffic)
kubectl scale deployment runner-standby-pool \
  --replicas=10 \
  -n production

# Or adjust HPA
kubectl patch hpa runner-standby-hpa \
  -n production \
  -p '{"spec":{"minReplicas":10}}'
```

---

## Cost Estimates

### Staging (2 Engineers)

| Resource | Spec | Monthly Cost |
|----------|------|--------------|
| GKE Cluster | 1x e2-medium (default) | ~$25 |
| GKE Sandbox Pool | 1-3x e2-standard-4 | ~$50-150 |
| Cloud SQL | db-f1-micro | ~$10 |
| Secrets, Logging, etc. | - | ~$10 |
| **Total** | | **~$100-200** |

### Production

| Resource | Spec | Monthly Cost |
|----------|------|--------------|
| GKE Cluster | 3x e2-standard-4 (default) | ~$200 |
| GKE Sandbox Pool | 2-20x e2-standard-4 | ~$150-600 |
| Cloud SQL | db-custom-2-8192 (HA) | ~$150 |
| Cloudflare | Pro | ~$20 |
| Monitoring, Logging | - | ~$50 |
| **Total** | | **~$500-1000** |

---

## Summary

| Environment | Purpose | Deploy Trigger | URL |
|-------------|---------|----------------|-----|
| Local | Fast iteration | Manual | localhost:3000 |
| Staging (per-engineer) | Full fidelity testing | Push to staging/* | {name}.staging.plue.dev |
| Production | Real users | Merge to main | plue.dev |

Key infrastructure decisions:
1. **Shared staging cluster, separate namespaces** — cost efficient, isolated
2. **Terraform for all infrastructure** — reproducible, version controlled
3. **Per-engineer databases** — no data conflicts
4. **Warm pool auto-scaling** — balance cost and latency
5. **gVisor only in staging/prod** — local dev is fast, CI ensures sandbox works
