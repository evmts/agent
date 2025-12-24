# External Secrets Operator - Quick Start

This guide provides a condensed workflow for setting up External Secrets Operator (ESO) for Plue.

## Prerequisites

- GKE cluster deployed
- Workload Identity enabled
- `kubectl` configured for the cluster
- `gcloud` authenticated

## 5-Minute Setup

### 1. Deploy Terraform Module

```bash
cd infra/terraform/environments/production
terraform apply -target=module.external_secrets
```

This creates:
- Helm release for ESO
- GCP service account with Secret Manager access
- Workload Identity binding

### 2. Run Setup Script

```bash
cd infra/k8s/external-secrets
./setup.sh <your-project-id> us-west1 plue-cluster
```

This script:
- Applies ClusterSecretStore
- Creates secrets in GCP Secret Manager
- Applies ExternalSecret manifests
- Waits for secrets to sync

**Important:** You'll be prompted for:
- Database URL (or use placeholder)
- Database password (or use placeholder)
- Anthropic API key (required)

JWT and session secrets are auto-generated.

### 3. Verify Setup

```bash
./verify.sh
```

This checks:
- ESO deployment is running
- ClusterSecretStore is ready
- ExternalSecrets are synced
- Kubernetes secrets are created

### 4. Update Pod Specs

Update your deployments to use the new secrets:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: plue
spec:
  template:
    spec:
      containers:
      - name: api
        envFrom:
        - secretRef:
            name: plue-database
        - secretRef:
            name: plue-api-secrets
```

### 5. Deploy and Test

```bash
kubectl rollout restart deployment/api -n plue
kubectl logs -n plue deployment/api --tail=50
```

## Manual Setup (Alternative)

If you prefer manual steps instead of the setup script:

### Step 1: Apply ClusterSecretStore

```bash
export PROJECT_ID="your-project-id"
export CLUSTER_REGION="us-west1"
export CLUSTER_NAME="plue-cluster"

envsubst < secret-store.yaml | kubectl apply -f -
```

### Step 2: Create Secrets in GCP

```bash
# Database credentials
echo -n "postgresql://user:pass@host:5432/plue" | \
  gcloud secrets create plue-database-url --data-file=-

echo -n "db-password" | \
  gcloud secrets create plue-database-password --data-file=-

# Anthropic API key
echo -n "sk-ant-api03-..." | \
  gcloud secrets create plue-anthropic-api-key --data-file=-

# JWT secret (auto-generate)
openssl rand -hex 64 | \
  gcloud secrets create plue-jwt-secret --data-file=-

# Session secret (auto-generate)
openssl rand -hex 64 | \
  gcloud secrets create plue-session-secret --data-file=-
```

### Step 3: Grant ESO Access

```bash
ESO_SA="plue-eso@${PROJECT_ID}.iam.gserviceaccount.com"

for secret in plue-database-url plue-database-password plue-anthropic-api-key plue-jwt-secret plue-session-secret; do
  gcloud secrets add-iam-policy-binding $secret \
    --member="serviceAccount:$ESO_SA" \
    --role="roles/secretmanager.secretAccessor"
done
```

### Step 4: Apply ExternalSecrets

```bash
kubectl apply -f database-secret.yaml
kubectl apply -f api-secrets.yaml
```

### Step 5: Wait for Sync

```bash
kubectl wait --for=condition=Ready externalsecret/database-credentials -n plue --timeout=120s
kubectl wait --for=condition=Ready externalsecret/api-secrets -n plue --timeout=120s
```

## Common Commands

### Check ESO Status

```bash
# ESO pods
kubectl get pods -n external-secrets

# ESO logs
kubectl logs -n external-secrets deployment/external-secrets -f
```

### Check Secrets Status

```bash
# ExternalSecrets
kubectl get externalsecrets -n plue
kubectl describe externalsecret database-credentials -n plue
kubectl describe externalsecret api-secrets -n plue

# Kubernetes Secrets
kubectl get secrets -n plue
kubectl get secret plue-database -n plue -o yaml
kubectl get secret plue-api-secrets -n plue -o yaml
```

### Force Secret Refresh

```bash
# Delete the K8s Secret to trigger immediate re-sync
kubectl delete secret plue-api-secrets -n plue

# ESO will recreate it within seconds
kubectl get secret plue-api-secrets -n plue
```

### Rotate a Secret

```bash
# 1. Update value in Secret Manager
echo -n "new-value" | gcloud secrets versions add plue-my-secret --data-file=-

# 2. Force sync (or wait up to 1 hour)
kubectl delete secret plue-api-secrets -n plue

# 3. Rolling restart pods
kubectl rollout restart deployment/api -n plue
```

## Troubleshooting

### ESO Pod Not Running

```bash
kubectl describe pod -n external-secrets -l app.kubernetes.io/name=external-secrets
kubectl logs -n external-secrets deployment/external-secrets --tail=100
```

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret api-secrets -n plue

# Common issues:
# - Secret doesn't exist in GCP Secret Manager
# - ESO service account lacks permissions
# - ClusterSecretStore misconfigured
```

### Verify Workload Identity

```bash
# Get into ESO pod
kubectl exec -n external-secrets deployment/external-secrets -it -- sh

# Check GCP service account
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

# Should output: plue-eso@PROJECT_ID.iam.gserviceaccount.com
```

### Check IAM Permissions

```bash
# Verify service account exists
gcloud iam service-accounts describe plue-eso@PROJECT_ID.iam.gserviceaccount.com

# Check secret access
gcloud secrets get-iam-policy plue-anthropic-api-key
```

## Next Steps

1. **Remove secrets from Terraform state**
   - Delete manual secret creation from Terraform
   - Remove sensitive values from `terraform.tfvars`

2. **Set up secret rotation schedule**
   - Create Cloud Scheduler jobs to rotate secrets
   - Update application to handle secret rotation gracefully

3. **Monitor secret access**
   - Enable Cloud Audit Logs for Secret Manager
   - Set up alerts for unauthorized access attempts

4. **Document secret management procedures**
   - Add to runbooks
   - Train team on secret rotation workflow

## Resources

- [Full documentation](README.md)
- [Terraform module documentation](../../../terraform/modules/external-secrets/README.md)
- [External Secrets Operator docs](https://external-secrets.io/)
- [GCP Secret Manager docs](https://cloud.google.com/secret-manager/docs)
