# External Secrets Operator Terraform Module

This module deploys External Secrets Operator (ESO) to a GKE cluster and configures Workload Identity for secure access to GCP Secret Manager.

## Purpose

External Secrets Operator eliminates the need to store secrets in Terraform state by:
- Syncing secrets from GCP Secret Manager into Kubernetes Secrets
- Using Workload Identity instead of service account keys
- Enabling automatic secret rotation with configurable refresh intervals
- Providing audit logging for all secret access

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ This Terraform Module Creates:                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Helm Release                                            │
│     • Deploys ESO chart to 'external-secrets' namespace     │
│     • Installs CRDs (ClusterSecretStore, ExternalSecret)    │
│     • Configures HA with 2 replicas                         │
│                                                             │
│  2. GCP Service Account                                     │
│     • Name: plue-eso@PROJECT.iam.gserviceaccount.com        │
│     • Roles: secretmanager.secretAccessor (project-wide)    │
│     • Roles: secretmanager.viewer (for listing)             │
│                                                             │
│  3. Workload Identity Binding                               │
│     • Binds K8s SA 'external-secrets' to GCP SA             │
│     • Enables ESO pods to auth without service account keys │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "external_secrets" {
  source = "../../modules/external-secrets"

  name_prefix         = "plue"
  project_id          = "my-gcp-project"
  namespace           = "external-secrets"
  eso_service_account = "external-secrets"

  labels = {
    app        = "plue"
    environment = "production"
    managed-by = "terraform"
  }

  providers = {
    google = google
    helm   = helm
  }

  depends_on = [module.gke]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for resource names | string | - | yes |
| project_id | GCP project ID | string | - | yes |
| namespace | K8s namespace to install ESO | string | "external-secrets" | no |
| eso_service_account | K8s service account name for ESO | string | "external-secrets" | no |
| labels | Labels to apply to GCP resources | map(string) | {...} | no |

## Outputs

| Name | Description |
|------|-------------|
| eso_service_account_email | Email of the GCP service account used by ESO |
| eso_service_account_name | Name of the GCP service account used by ESO |
| namespace | Kubernetes namespace where ESO is installed |
| helm_release_name | Name of the ESO Helm release |
| helm_release_status | Status of the ESO Helm release |

## Post-Deployment Steps

After applying this module, you must:

1. **Apply ClusterSecretStore manifest** (connects ESO to GCP Secret Manager):
   ```bash
   cd infra/k8s/external-secrets
   export PROJECT_ID="your-project"
   export CLUSTER_REGION="us-west1"
   export CLUSTER_NAME="plue-cluster"
   envsubst < secret-store.yaml | kubectl apply -f -
   ```

2. **Create secrets in GCP Secret Manager**:
   ```bash
   # Database credentials
   echo -n "postgresql://..." | gcloud secrets create plue-database-url --data-file=-

   # API secrets
   echo -n "sk-ant-..." | gcloud secrets create plue-anthropic-api-key --data-file=-
   openssl rand -hex 64 | gcloud secrets create plue-jwt-secret --data-file=-
   openssl rand -hex 64 | gcloud secrets create plue-session-secret --data-file=-
   ```

3. **Apply ExternalSecret manifests** (tells ESO which secrets to sync):
   ```bash
   kubectl apply -f database-secret.yaml
   kubectl apply -f api-secrets.yaml
   ```

4. **Verify secrets are synced**:
   ```bash
   kubectl get externalsecrets -n plue
   kubectl get secrets -n plue
   ```

See [infra/k8s/external-secrets/README.md](../../../k8s/external-secrets/README.md) for detailed instructions.

## How ESO Works

1. **ESO Controller** watches for `ExternalSecret` custom resources
2. **Fetches secrets** from GCP Secret Manager using the `ClusterSecretStore` configuration
3. **Creates K8s Secrets** with the fetched data in the target namespace
4. **Refreshes automatically** every hour (configurable via `refreshInterval`)
5. **Pods mount** these secrets like normal K8s secrets (no code changes needed)

## Security Features

- **Workload Identity**: No service account keys stored anywhere
- **Encryption at rest**: Secrets encrypted in etcd by GKE
- **Audit logging**: GCP Secret Manager logs all access
- **Fine-grained IAM**: Can restrict ESO to specific secrets
- **No Terraform state**: Secrets never stored in Terraform state
- **Version pinning**: Supports pinning to specific secret versions

## Secret Rotation

To rotate a secret:

1. Update the secret value in GCP Secret Manager:
   ```bash
   echo -n "new-value" | gcloud secrets versions add plue-my-secret --data-file=-
   ```

2. Wait up to 1 hour for ESO to sync (or force immediate sync):
   ```bash
   kubectl delete secret plue-api-secrets -n plue
   ```

3. Rolling restart pods to pick up the new value:
   ```bash
   kubectl rollout restart deployment/api -n plue
   ```

## Troubleshooting

### Check ESO logs
```bash
kubectl logs -n external-secrets deployment/external-secrets -f
```

### Verify Workload Identity is working
```bash
# Exec into ESO pod
kubectl exec -n external-secrets deployment/external-secrets -it -- sh

# Try to access GCP metadata (should work)
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
```

### Check IAM permissions
```bash
# Verify service account exists
gcloud iam service-accounts describe plue-eso@PROJECT.iam.gserviceaccount.com

# Check IAM bindings
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:plue-eso@*"
```

### Common Issues

**"Failed to get secret: Permission denied"**
- ESO service account lacks `secretmanager.secretAccessor` role
- Check IAM policy: `gcloud secrets get-iam-policy plue-my-secret`

**"Failed to initialize provider: invalid configuration"**
- ClusterSecretStore not applied or misconfigured
- Check: `kubectl get clustersecretstore -o yaml`

**"Helm release not found"**
- Helm provider not authenticated to cluster
- Verify: `helm list -n external-secrets`

## Migration Strategy

To migrate from Terraform-managed secrets to ESO:

1. Deploy this module
2. Create secrets in Secret Manager with same values as Terraform
3. Apply ExternalSecrets
4. Update pod specs to reference new secret names
5. Verify pods work with new secrets
6. Remove secret creation from Terraform
7. Remove sensitive values from `terraform.tfvars`

## Resources Created

- `google_service_account.eso` - GCP service account for ESO
- `google_project_iam_member.eso_secret_accessor` - IAM role binding
- `google_project_iam_member.eso_secret_viewer` - IAM role binding (optional)
- `google_service_account_iam_member.eso_workload_identity` - Workload Identity binding
- `helm_release.external_secrets` - ESO Helm chart

## Dependencies

- GKE cluster must be deployed
- Workload Identity must be enabled on the cluster
- Helm and Kubernetes providers must be configured

## Version Compatibility

- Terraform >= 1.5.0
- Helm provider >= 2.12
- Google provider >= 5.0
- External Secrets Operator chart >= 0.9.11
- Kubernetes >= 1.24

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [GCP Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [GKE Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
