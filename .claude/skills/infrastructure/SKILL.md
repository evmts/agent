---
name: infrastructure
description: Plue deployment, environments, and infrastructure. Use when working with Docker, Kubernetes, Terraform, or deployment.
---

# Plue Infrastructure

For full details, see: `docs/infrastructure.md`

## Environments

| Environment | Stack | URL |
|-------------|-------|-----|
| Local | Docker Compose | localhost:3000 |
| Staging | GKE + gVisor | {name}.staging.plue.dev |
| Production | GKE + gVisor (HA) | plue.dev |

## Local Development

```bash
zig build run          # Start docker + server
zig build run:web      # Start Astro dev server (separate terminal)
```

## Key Infrastructure

- **Compute**: GKE with gVisor node pool for sandboxing
- **Database**: Cloud SQL (PostgreSQL 16)
- **CDN**: Cloudflare
- **IaC**: Terraform in `terraform/`
- **CI/CD**: GitHub Actions → GKE

## Terraform Structure

```
terraform/
├── modules/           # Reusable: gke-cluster, cloud-sql, staging-namespace
└── environments/      # staging-base, staging-{name}, production
```

## Docker Services

```bash
docker compose up -d postgres    # Just database
docker compose up -d             # All services
```
