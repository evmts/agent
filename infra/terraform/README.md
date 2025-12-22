# Plue Terraform Infrastructure

Deploy Plue to Google Cloud Platform with GKE, Cloud SQL, and Cloudflare DNS.

## Architecture

```
                    [Cloudflare DNS/CDN]
                           |
                    [GKE LoadBalancer]
                           |
              +------------+------------+
              |            |            |
          [Web:5173]  [API:4000]  [Electric:3000]
              |            |            |
              +------------+------------+
                           |
                   [Cloud SQL PostgreSQL]
```

## Prerequisites

1. **GCP Account** with:
   - Organization ID
   - Billing Account ID
   - `gcloud` CLI installed and authenticated

2. **Cloudflare Account** with:
   - Domain added to Cloudflare
   - API token with Zone:Edit, DNS:Edit permissions
   - Zone ID

3. **Tools**:
   - Terraform >= 1.5.0
   - Docker (for building images)

## Quick Start

### 1. Create Terraform State Bucket

```bash
# Create a globally unique bucket name
BUCKET_NAME="plue-terraform-state-$(date +%s)"
gsutil mb -l us-west1 gs://$BUCKET_NAME
gsutil versioning set on gs://$BUCKET_NAME

# Update backend.tf with your bucket name
```

### 2. Configure Variables

```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Deploy in stages (recommended for first deployment)

# Stage 1: GCP Project and APIs
terraform apply -target=module.project

# Stage 2: Networking
terraform apply -target=module.networking

# Stage 3: Database
terraform apply -target=module.cloudsql

# Stage 4: GKE, Secrets, Registry
terraform apply -target=module.gke
terraform apply -target=module.secrets
terraform apply -target=module.artifact_registry

# Stage 5: Build and push Docker images
# See output: docker_push_commands

# Stage 6: Add ANTHROPIC_API_KEY to Secret Manager
# See output: add_anthropic_key_command

# Stage 7: Deploy Kubernetes resources
terraform apply -target=module.kubernetes

# Stage 8: Configure DNS
terraform apply -target=module.dns
```

### 4. Build and Push Docker Images

```bash
# Get registry URL from Terraform output
REGISTRY=$(terraform output -raw registry_url)

# Authenticate Docker
gcloud auth configure-docker us-west1-docker.pkg.dev

# Build and push from project root
cd ../../..
docker build --target api -t $REGISTRY/plue-api:latest .
docker push $REGISTRY/plue-api:latest

docker build --target web -t $REGISTRY/plue-web:latest .
docker push $REGISTRY/plue-web:latest
```

### 5. Add ANTHROPIC_API_KEY

```bash
# Get secret name from output
SECRET_ID=$(terraform output -raw anthropic_api_key_secret)

# Add your API key
echo -n 'sk-ant-xxxxx' | gcloud secrets versions add $SECRET_ID --data-file=-
```

### 6. Access Your Application

After deployment completes:

```bash
terraform output web_url
# https://plue.yourdomain.com

terraform output api_url
# https://api.plue.yourdomain.com
```

## Module Structure

```
terraform/
├── environments/
│   └── production/       # Root module for production
├── modules/
│   ├── project/          # GCP project + APIs
│   ├── networking/       # VPC, subnets, NAT
│   ├── gke/              # GKE cluster + node pools
│   ├── cloudsql/         # PostgreSQL 16
│   ├── artifact-registry/# Container registry
│   ├── secrets/          # Secret Manager + Workload Identity
│   └── dns/              # Cloudflare DNS
└── kubernetes/           # K8s resources (namespace, deployments, ingress)
```

## Key Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Compute | GKE Standard | WebSocket support, persistent volumes, Workload Identity |
| Database | Cloud SQL PostgreSQL 16 | Managed, HA, logical replication for ElectricSQL |
| Storage | SSD Persistent Disks | Fast I/O for Electric and git repos |
| Ingress | nginx-ingress | Better WebSocket support than GCE Ingress |
| DNS/CDN | Cloudflare | DDoS protection, edge caching, easy SSL |
| Secrets | Secret Manager | Audit logging, rotation, IAM integration |

## Costs (Estimated)

| Resource | Monthly Cost |
|----------|-------------|
| GKE (3x e2-standard-4) | ~$300 |
| Cloud SQL (db-custom-2-8192, HA) | ~$150 |
| Load Balancer | ~$20 |
| Persistent Disks (150GB SSD) | ~$25 |
| Cloud NAT | ~$30 |
| **Total** | **~$525/month** |

Cost can be reduced by:
- Using smaller machine types
- Disabling HA on Cloud SQL
- Using preemptible/spot nodes

## Troubleshooting

### Get GKE credentials

```bash
$(terraform output -raw gke_get_credentials_command)
```

### Check pod status

```bash
kubectl get pods -n plue
kubectl logs -n plue deployment/api
kubectl logs -n plue deployment/web
kubectl logs -n plue deployment/electric
```

### Check ingress

```bash
kubectl get ingress -n plue
kubectl describe ingress plue-ingress -n plue
```

### Database connection

```bash
# Get Cloud SQL connection name
terraform output cloudsql_connection_name

# Use Cloud SQL Proxy for local access
cloud-sql-proxy PROJECT:REGION:INSTANCE --port 5433
psql -h localhost -p 5433 -U postgres -d electric
```

## Cleanup

```bash
# Disable deletion protection first
terraform apply -var="deletion_protection=false"

# Destroy all resources
terraform destroy
```

**Warning**: This will delete all data including the database and git repos!
