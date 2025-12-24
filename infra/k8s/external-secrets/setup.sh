#!/bin/bash
# =============================================================================
# External Secrets Operator Setup Script
# =============================================================================
# This script helps set up External Secrets Operator for Plue.
#
# Prerequisites:
# - Terraform module 'external_secrets' deployed
# - kubectl configured for GKE cluster
# - gcloud authenticated with appropriate permissions
#
# Usage:
#   ./setup.sh <project-id> <cluster-region> <cluster-name>
#
# Example:
#   ./setup.sh plue-production us-west1 plue-cluster

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

PROJECT_ID="${1:-}"
CLUSTER_REGION="${2:-us-west1}"
CLUSTER_NAME="${3:-plue-cluster}"
ESO_SA="plue-eso@${PROJECT_ID}.iam.gserviceaccount.com"

if [ -z "$PROJECT_ID" ]; then
  echo "Error: PROJECT_ID is required"
  echo "Usage: $0 <project-id> [cluster-region] [cluster-name]"
  exit 1
fi

echo "==================================================================="
echo "External Secrets Operator Setup for Plue"
echo "==================================================================="
echo "Project ID:      $PROJECT_ID"
echo "Cluster Region:  $CLUSTER_REGION"
echo "Cluster Name:    $CLUSTER_NAME"
echo "ESO SA:          $ESO_SA"
echo "==================================================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: Apply ClusterSecretStore
# -----------------------------------------------------------------------------

echo "Step 1: Applying ClusterSecretStore..."
export PROJECT_ID CLUSTER_REGION CLUSTER_NAME
envsubst < secret-store.yaml | kubectl apply -f -
echo "✓ ClusterSecretStore created"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Create secrets in GCP Secret Manager
# -----------------------------------------------------------------------------

echo "Step 2: Creating secrets in GCP Secret Manager..."

# Function to create or update secret
create_secret() {
  local secret_name=$1
  local secret_value=$2
  local description=$3

  if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  • $secret_name already exists, adding new version"
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
      --project="$PROJECT_ID" \
      --data-file=-
  else
    echo "  • Creating $secret_name"
    gcloud secrets create "$secret_name" \
      --project="$PROJECT_ID" \
      --replication-policy=automatic \
      --labels=app=plue,managed-by=eso-setup
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
      --project="$PROJECT_ID" \
      --data-file=-
  fi

  # Grant ESO access
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:$ESO_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet >/dev/null 2>&1 || true
}

# Database URL (placeholder - user should update)
read -p "Enter DATABASE_URL (or press Enter to use placeholder): " db_url
db_url=${db_url:-"postgresql://plue:changeme@localhost:5432/plue"}
create_secret "plue-database-url" "$db_url"

# Database password (placeholder - user should update)
read -p "Enter DATABASE_PASSWORD (or press Enter to use placeholder): " db_pass
db_pass=${db_pass:-"changeme"}
create_secret "plue-database-password" "$db_pass"

# Anthropic API key (user must provide)
echo ""
echo "IMPORTANT: You must provide your Anthropic API key"
read -sp "Enter ANTHROPIC_API_KEY: " anthropic_key
echo ""
if [ -z "$anthropic_key" ]; then
  echo "Warning: No Anthropic API key provided. You must add it manually later:"
  echo "  echo -n 'sk-ant-api03-...' | gcloud secrets versions add plue-anthropic-api-key --data-file=-"
  anthropic_key="CHANGEME"
fi
create_secret "plue-anthropic-api-key" "$anthropic_key"

# JWT secret (auto-generate)
jwt_secret=$(openssl rand -hex 64)
create_secret "plue-jwt-secret" "$jwt_secret"

# Session secret (auto-generate)
session_secret=$(openssl rand -hex 64)
create_secret "plue-session-secret" "$session_secret"

echo "✓ All secrets created in GCP Secret Manager"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Apply ExternalSecret manifests
# -----------------------------------------------------------------------------

echo "Step 3: Applying ExternalSecret manifests..."
kubectl apply -f database-secret.yaml
kubectl apply -f api-secrets.yaml
echo "✓ ExternalSecrets created"
echo ""

# -----------------------------------------------------------------------------
# Step 4: Wait for secrets to sync
# -----------------------------------------------------------------------------

echo "Step 4: Waiting for secrets to sync (this may take a minute)..."
echo "  • Waiting for plue-database secret..."
kubectl wait --for=condition=Ready externalsecret/database-credentials -n plue --timeout=120s

echo "  • Waiting for plue-api-secrets secret..."
kubectl wait --for=condition=Ready externalsecret/api-secrets -n plue --timeout=120s

echo "✓ All secrets synced successfully"
echo ""

# -----------------------------------------------------------------------------
# Step 5: Verify
# -----------------------------------------------------------------------------

echo "Step 5: Verifying secrets..."
echo ""
echo "ExternalSecrets status:"
kubectl get externalsecrets -n plue
echo ""
echo "Kubernetes Secrets created:"
kubectl get secrets -n plue | grep plue-
echo ""

# -----------------------------------------------------------------------------
# Complete
# -----------------------------------------------------------------------------

echo "==================================================================="
echo "✓ External Secrets Operator setup complete!"
echo "==================================================================="
echo ""
echo "Next steps:"
echo "1. Update DATABASE_URL and DATABASE_PASSWORD with real values:"
echo "   echo -n 'postgresql://...' | gcloud secrets versions add plue-database-url --data-file=-"
echo ""
echo "2. If you didn't provide Anthropic API key, add it now:"
echo "   echo -n 'sk-ant-api03-...' | gcloud secrets versions add plue-anthropic-api-key --data-file=-"
echo ""
echo "3. Restart pods to pick up secrets:"
echo "   kubectl rollout restart deployment/api -n plue"
echo ""
echo "4. Monitor ESO logs:"
echo "   kubectl logs -n external-secrets deployment/external-secrets -f"
echo ""
