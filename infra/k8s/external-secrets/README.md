# External Secrets Operator - Secret Management

External Secrets Operator (ESO) syncs secrets from GCP Secret Manager into Kubernetes, eliminating secrets from Terraform state and enabling secure secret rotation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         GKE Cluster                         │
│                                                             │
│  ┌──────────────┐      ┌───────────────────────────┐       │
│  │ ESO Pod      │      │ Plue API Pod              │       │
│  │              │      │                           │       │
│  │ • Watches    │      │ • Mounts K8s Secret       │       │
│  │   External   │──────┤ • Reads env vars          │       │
│  │   Secrets    │      │ • No GCP API calls needed │       │
│  │              │      │                           │       │
│  │ • Uses       │      └───────────────────────────┘       │
│  │   Workload   │                                          │
│  │   Identity   │                                          │
│  └──────┬───────┘                                          │
│         │                                                  │
└─────────┼──────────────────────────────────────────────────┘
          │
          │ Workload Identity
          │ (no service account keys)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                   GCP Secret Manager                        │
│                                                             │
│  • plue-database-url                                        │
│  • plue-database-password                                   │
│  • plue-anthropic-api-key                                   │
│  • plue-jwt-secret                                          │
│  • plue-session-secret                                      │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

1. **ESO Controller** watches `ExternalSecret` custom resources
2. **Fetches secrets** from GCP Secret Manager using Workload Identity
3. **Creates K8s Secrets** with the synced data
4. **Pods mount** these secrets like normal (no code changes)
5. **Auto-refreshes** every hour to detect secret changes

## Files

- `secret-store.yaml` - ClusterSecretStore for GCP Secret Manager
- `database-secret.yaml` - ExternalSecret for database credentials
- `api-secrets.yaml` - ExternalSecret for API secrets (Anthropic, JWT, session)

## Deployment

### Prerequisites

1. Deploy Terraform module to install ESO and configure IAM:
   ```bash
   cd infra/terraform/environments/production
   terraform apply -target=module.external_secrets
   ```

2. Apply the ClusterSecretStore (replace placeholders):
   ```bash
   export PROJECT_ID="your-gcp-project"
   export CLUSTER_REGION="us-west1"
   export CLUSTER_NAME="plue-cluster"

   envsubst < secret-store.yaml | kubectl apply -f -
   ```

3. Create secrets in GCP Secret Manager:
   ```bash
   # Database URL
   echo -n "postgresql://user:pass@host:5432/plue" | \
     gcloud secrets create plue-database-url \
       --data-file=- \
       --replication-policy=automatic

   # Database password (if separate)
   echo -n "db-password" | \
     gcloud secrets create plue-database-password \
       --data-file=- \
       --replication-policy=automatic

   # Anthropic API key
   gcloud secrets create plue-anthropic-api-key \
     --replication-policy=automatic
   echo -n "sk-ant-api03-..." | \
     gcloud secrets versions add plue-anthropic-api-key --data-file=-

   # JWT secret (auto-generate)
   openssl rand -hex 64 | \
     gcloud secrets create plue-jwt-secret \
       --data-file=- \
       --replication-policy=automatic

   # Session secret (auto-generate)
   openssl rand -hex 64 | \
     gcloud secrets create plue-session-secret \
       --data-file=- \
       --replication-policy=automatic
   ```

4. Apply ExternalSecrets:
   ```bash
   kubectl apply -f database-secret.yaml
   kubectl apply -f api-secrets.yaml
   ```

5. Verify secrets were created:
   ```bash
   # Check ExternalSecret status
   kubectl get externalsecrets -n plue
   kubectl describe externalsecret database-credentials -n plue
   kubectl describe externalsecret api-secrets -n plue

   # Check that K8s Secrets were created
   kubectl get secrets -n plue
   kubectl get secret plue-database -n plue -o yaml
   kubectl get secret plue-api-secrets -n plue -o yaml
   ```

## Secret Rotation

### Database Credentials

```bash
# 1. Change password in PostgreSQL
psql -c "ALTER USER plue_user WITH PASSWORD 'new-password';"

# 2. Update secret in GCP
echo -n "new-password" | \
  gcloud secrets versions add plue-database-password --data-file=-

# 3. Wait up to 1 hour for ESO to sync (or force sync)
kubectl delete secret plue-database -n plue

# 4. Rolling restart to pick up new value
kubectl rollout restart deployment/api -n plue

# 5. Verify connectivity
kubectl logs -n plue deployment/api --tail=50
```

### Anthropic API Key

```bash
# 1. Generate new key in Anthropic console

# 2. Add new version to Secret Manager
echo -n "sk-ant-api03-NEW-KEY" | \
  gcloud secrets versions add plue-anthropic-api-key --data-file=-

# 3. Force immediate sync (or wait 1 hour)
kubectl delete secret plue-api-secrets -n plue

# 4. Rolling restart
kubectl rollout restart deployment/api -n plue

# 5. Verify API works, then disable old key
```

### JWT Secret (Warning: Invalidates all tokens)

```bash
# 1. Generate new secret
openssl rand -hex 64 | \
  gcloud secrets versions add plue-jwt-secret --data-file=-

# 2. ESO syncs within 1 hour
# 3. Rolling restart (users must re-authenticate)
kubectl rollout restart deployment/api -n plue
```

### Session Secret (Warning: Invalidates all sessions)

```bash
# 1. Generate new secret
openssl rand -hex 64 | \
  gcloud secrets versions add plue-session-secret --data-file=-

# 2. ESO syncs within 1 hour
# 3. Rolling restart (users must re-login)
kubectl rollout restart deployment/api -n plue
```

## Adding New Secrets

1. Create secret in GCP Secret Manager:
   ```bash
   echo -n "secret-value" | \
     gcloud secrets create plue-my-new-secret \
       --data-file=- \
       --replication-policy=automatic
   ```

2. Grant ESO access:
   ```bash
   gcloud secrets add-iam-policy-binding plue-my-new-secret \
     --member="serviceAccount:plue-eso@PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```

3. Add to ExternalSecret (e.g., `api-secrets.yaml`):
   ```yaml
   data:
     - secretKey: MY_NEW_SECRET
       remoteRef:
         key: plue-my-new-secret
         version: latest
   ```

4. Apply changes:
   ```bash
   kubectl apply -f api-secrets.yaml
   ```

5. ESO will sync the new secret within refreshInterval (1h)

## Troubleshooting

### Check ESO logs
```bash
kubectl logs -n external-secrets deployment/external-secrets -f
```

### Check ExternalSecret status
```bash
kubectl describe externalsecret api-secrets -n plue
kubectl describe externalsecret database-credentials -n plue
```

### Common issues

**"Failed to get secret from provider"**
- Check that secret exists in GCP Secret Manager
- Verify ESO service account has `secretAccessor` role
- Check Workload Identity binding is correct

**"Secret not syncing"**
- Default refresh is 1 hour - be patient or force sync
- Delete the K8s Secret to trigger immediate sync
- Check ESO controller logs for errors

**"Pods can't read secret"**
- Verify K8s Secret exists: `kubectl get secret plue-api-secrets -n plue`
- Check pod's namespace matches ExternalSecret namespace
- Verify secret is mounted correctly in pod spec

## Migration from Terraform Secrets

To migrate from Terraform-managed secrets to ESO:

1. Deploy ESO module
2. Create secrets in Secret Manager with same values as Terraform
3. Apply ExternalSecrets
4. Update pod specs to reference new secret names
5. Remove secret creation from Terraform
6. Remove sensitive values from terraform.tfvars

## Security Notes

- **Workload Identity** eliminates service account keys
- **Secrets encrypted** at rest in etcd by GKE
- **No secrets** stored in Terraform state
- **Audit logging** in GCP Secret Manager tracks all access
- **Fine-grained IAM** can restrict ESO to specific secrets
- **Version pinning** available for rollback safety
