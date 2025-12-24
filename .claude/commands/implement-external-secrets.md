# Implement External Secrets Operator

## Priority: HIGH | Security

## Problem

Secrets are currently synced via Terraform, causing them to appear in state files:

`infra/terraform/kubernetes/secrets.tf:13-26`
- Secrets stored in Terraform state (potentially unencrypted)
- No automatic rotation when secrets change
- State file becomes a high-value target

## Task

1. **Install External Secrets Operator:**
   ```bash
   # Add Helm repo
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update

   # Install ESO
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace \
     --set installCRDs=true
   ```

2. **Create Terraform module for ESO:**
   ```terraform
   # infra/terraform/modules/external-secrets/main.tf

   resource "helm_release" "external_secrets" {
     name             = "external-secrets"
     repository       = "https://charts.external-secrets.io"
     chart            = "external-secrets"
     namespace        = "external-secrets"
     create_namespace = true
     version          = "0.9.11"

     set {
       name  = "installCRDs"
       value = "true"
     }
   }
   ```

3. **Create SecretStore for GCP:**
   ```yaml
   # infra/k8s/external-secrets/secret-store.yaml

   apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: gcp-secret-manager
   spec:
     provider:
       gcpsm:
         projectID: plue-prod  # Use variable
         auth:
           workloadIdentity:
             clusterLocation: us-west1
             clusterName: plue-cluster
             serviceAccountRef:
               name: external-secrets-sa
               namespace: external-secrets
   ```

4. **Create ExternalSecret for database:**
   ```yaml
   # infra/k8s/external-secrets/database-secret.yaml

   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: database-credentials
     namespace: plue
   spec:
     refreshInterval: 1h
     secretStoreRef:
       kind: ClusterSecretStore
       name: gcp-secret-manager
     target:
       name: database-credentials
       creationPolicy: Owner
     data:
       - secretKey: DATABASE_URL
         remoteRef:
           key: plue-database-url
       - secretKey: DATABASE_PASSWORD
         remoteRef:
           key: plue-database-password
   ```

5. **Create ExternalSecret for API keys:**
   ```yaml
   # infra/k8s/external-secrets/api-secrets.yaml

   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: api-credentials
     namespace: plue
   spec:
     refreshInterval: 1h
     secretStoreRef:
       kind: ClusterSecretStore
       name: gcp-secret-manager
     target:
       name: api-credentials
       creationPolicy: Owner
     data:
       - secretKey: ANTHROPIC_API_KEY
         remoteRef:
           key: anthropic-api-key
       - secretKey: JWT_SECRET
         remoteRef:
           key: jwt-secret
       - secretKey: SESSION_SECRET
         remoteRef:
           key: session-secret
   ```

6. **Configure Workload Identity for ESO:**
   ```terraform
   # infra/terraform/modules/external-secrets/iam.tf

   resource "google_service_account" "external_secrets" {
     account_id   = "external-secrets-sa"
     display_name = "External Secrets Operator"
   }

   resource "google_project_iam_member" "secret_accessor" {
     project = var.project_id
     role    = "roles/secretmanager.secretAccessor"
     member  = "serviceAccount:${google_service_account.external_secrets.email}"
   }

   resource "google_service_account_iam_binding" "workload_identity" {
     service_account_id = google_service_account.external_secrets.name
     role               = "roles/iam.workloadIdentityUser"
     members = [
       "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets-sa]"
     ]
   }
   ```

7. **Remove secrets from Terraform state:**
   ```bash
   # Remove from state (secrets already exist in cluster)
   terraform state rm kubernetes_secret.database_credentials
   terraform state rm kubernetes_secret.api_credentials

   # Delete the old Terraform secret resources
   # infra/terraform/kubernetes/secrets.tf - remove or comment out
   ```

8. **Update deployments to use new secrets:**
   ```yaml
   # Verify existing secretRef names match new ExternalSecret target names
   envFrom:
     - secretRef:
         name: database-credentials
     - secretRef:
         name: api-credentials
   ```

9. **Add monitoring:**
   ```yaml
   # Alert when secret sync fails
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: external-secrets-alerts
   spec:
     groups:
       - name: external-secrets
         rules:
           - alert: ExternalSecretSyncFailed
             expr: externalsecret_status_condition{condition="Ready", status="False"} == 1
             for: 5m
             labels:
               severity: critical
             annotations:
               summary: "External secret sync failed"
   ```

10. **Document rotation procedure:**
    ```markdown
    ## Secret Rotation

    1. Update secret in GCP Secret Manager
    2. Wait for ESO refresh (default: 1 hour) or force sync:
       ```bash
       kubectl annotate externalsecret database-credentials \
         force-sync=$(date +%s) --overwrite
       ```
    3. Verify secret updated:
       ```bash
       kubectl get secret database-credentials -o yaml
       ```
    4. Restart affected deployments if needed
    ```

## Acceptance Criteria

- [ ] External Secrets Operator installed and running
- [ ] All secrets synced from GCP Secret Manager
- [ ] Workload Identity configured (no service account keys)
- [ ] Old secrets removed from Terraform state
- [ ] Secret rotation tested and documented
- [ ] Monitoring alerts configured
