# Scripts

Deployment automation and infrastructure utilities.

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-staging.sh` | Deploy to per-engineer staging namespace |
| `init-my-staging.sh` | Initialize personal staging environment |
| `generate-mtls-certs.sh` | Generate mTLS certificates for Cloudflare |

## deploy-staging.sh

Automated deployment to per-engineer staging environments.

**Usage:**
```bash
./deploy-staging.sh
```

**Environment variables:**
```bash
STAGING_NAMESPACE=$USER  # Defaults to your username
```

**What it does:**
1. Get current git SHA and branch
2. Authenticate with GCR (Google Container Registry)
3. Build API and runner images
4. Push images with SHA tag
5. Get GKE cluster credentials
6. Create namespace if needed
7. Deploy with Helm (values-staging.yaml + SHA tag)

**Example:**
```bash
# Deploy to your personal namespace (wc-staging)
./deploy-staging.sh

# Deploy to different namespace
STAGING_NAMESPACE=feature-test ./deploy-staging.sh
```

**Workflow:**
```
Local code
    ├─→ docker build (API, runner)
    ├─→ docker push (gcr.io/plue-staging/<image>:<git-sha>)
    └─→ helm upgrade --install plue
            ├─→ namespace: $USER
            ├─→ values: values-staging.yaml
            └─→ image.tag: <git-sha>
```

## init-my-staging.sh

Initialize a new personal staging environment with required secrets and configuration.

**Usage:**
```bash
./init-my-staging.sh
```

**What it does:**
1. Create namespace ($USER)
2. Create ServiceAccount with RBAC
3. Copy secrets from staging-shared namespace
4. Apply network policies
5. Setup External Secrets Operator bindings
6. Create initial PDBs

**Prerequisites:**
- GKE cluster access
- kubectl configured
- Permissions to create namespaces

**First-time setup:**
```bash
# Initialize your staging environment
./init-my-staging.sh

# Then deploy
./deploy-staging.sh
```

## generate-mtls-certs.sh

Generate custom CA and client certificates for Cloudflare Authenticated Origin Pulls (mTLS).

**Why custom certificates?**
Cloudflare provides shared certificates for mTLS, but anyone using Cloudflare could point their domain at your origin. Custom certificates ensure only YOUR Cloudflare account can connect.

**Usage:**
```bash
./generate-mtls-certs.sh [output_dir]
```

**Default output:** `./certs/`

**Generated files:**

| File | Description | Usage |
|------|-------------|-------|
| `ca.key` | CA private key | Keep secret! |
| `ca.crt` | CA certificate | Configure on origin server (API ingress) |
| `client.key` | Client private key | Intermediate artifact |
| `client.crt` | Client certificate | Intermediate artifact |
| `client.pem` | Combined client cert + key | Upload to Cloudflare dashboard |

**Workflow:**
```
1. Generate CA (10 year validity)
    ├─→ ca.key (keep secret)
    └─→ ca.crt (configure on origin)

2. Generate client certificate
    ├─→ client.key
    ├─→ client.crt
    └─→ client.pem (upload to Cloudflare)

3. Configure Cloudflare:
    SSL/TLS → Origin Server
        └─→ Upload client.pem

4. Configure GKE Ingress:
    SSL annotation: client-cert-secret
        └─→ kubectl create secret generic client-cert \
              --from-file=ca.crt=certs/ca.crt
```

**Certificate details:**
- CA: 4096-bit RSA, 10 year validity
- Client: 4096-bit RSA, signed by CA
- Subject: CN=Plue Origin CA/O=Plue/C=US

**Security:**
- `ca.key` must be kept secret (can sign new client certs)
- `client.pem` is uploaded to Cloudflare (less sensitive)
- `ca.crt` is public (only validates signatures)

**Rotation:**
Generate new client certificates anytime:
```bash
# Keep same CA, regenerate client cert
./generate-mtls-certs.sh ./certs-new
# Upload new client.pem to Cloudflare
# Update ingress secret with new ca.crt
```

## Common Workflows

**Set up new staging environment:**
```bash
./init-my-staging.sh
./deploy-staging.sh
```

**Deploy after making changes:**
```bash
git add . && git commit -m "feat: new feature"
./deploy-staging.sh
```

**Set up mTLS (one-time):**
```bash
./generate-mtls-certs.sh
kubectl create secret generic cloudflare-origin-ca \
  --from-file=ca.crt=certs/ca.crt \
  -n production
# Then upload certs/client.pem to Cloudflare dashboard
```

## Environment Variables

**deploy-staging.sh:**
- `STAGING_NAMESPACE`: Target namespace (default: $USER)
- `PROJECT_ID`: GCP project (default: plue-staging)
- `CLUSTER`: GKE cluster name (default: plue-staging)
- `REGION`: GCP region (default: us-central1)

**generate-mtls-certs.sh:**
- None (pass output dir as argument)

## Troubleshooting

**deploy-staging.sh fails with auth error:**
```bash
gcloud auth login
gcloud auth configure-docker gcr.io
```

**Namespace already exists:**
init-my-staging.sh is idempotent—safe to run multiple times.

**mTLS not working:**
- Verify ca.crt matches client.pem CA
- Check Cloudflare SSL/TLS mode is "Full (strict)"
- Check ingress has correct annotation: `nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"`
- Check secret exists: `kubectl get secret cloudflare-origin-ca -n production`

**Image pull errors:**
- Verify GCR authentication: `docker pull gcr.io/plue-staging/zig-api:latest`
- Check ServiceAccount has ImagePullSecrets
- Check image exists: `gcloud container images list --repository=gcr.io/plue-staging`
