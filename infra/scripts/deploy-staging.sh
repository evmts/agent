#!/bin/bash
# Deploy to per-engineer staging environment

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
  -f helm/plue/values-staging.yaml \
  --wait \
  --timeout 5m

# Wait for rollout
echo "→ Waiting for rollout..."
kubectl rollout status deployment/plue -n ${NAMESPACE} --timeout=5m

echo "══════════════════════════════════════════════════════════════"
echo "  ✓ Deployed successfully!"
echo "  URL: https://${NAMESPACE}.staging.plue.dev"
echo "══════════════════════════════════════════════════════════════"
