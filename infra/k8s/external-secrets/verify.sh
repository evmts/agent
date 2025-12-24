#!/bin/bash
# =============================================================================
# External Secrets Operator Verification Script
# =============================================================================
# Verifies that ESO is correctly installed and configured.
#
# Usage:
#   ./verify.sh

set -euo pipefail

echo "==================================================================="
echo "External Secrets Operator Verification"
echo "==================================================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check counter
CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
  local description=$1
  local command=$2

  echo -n "Checking: $description... "

  if eval "$command" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((CHECKS_PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC}"
    ((CHECKS_FAILED++))
    return 1
  fi
}

check_with_output() {
  local description=$1
  local command=$2

  echo "Checking: $description"
  eval "$command"
  echo ""
}

# -----------------------------------------------------------------------------
# Check 1: ESO Namespace
# -----------------------------------------------------------------------------

check "ESO namespace exists" \
  "kubectl get namespace external-secrets"

# -----------------------------------------------------------------------------
# Check 2: ESO Deployment
# -----------------------------------------------------------------------------

check "ESO deployment exists" \
  "kubectl get deployment external-secrets -n external-secrets"

check "ESO pods are running" \
  "kubectl get pods -n external-secrets -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].status.phase}' | grep -q Running"

# -----------------------------------------------------------------------------
# Check 3: ESO Service Account
# -----------------------------------------------------------------------------

check "ESO Kubernetes service account exists" \
  "kubectl get serviceaccount external-secrets -n external-secrets"

# Check Workload Identity annotation
if kubectl get serviceaccount external-secrets -n external-secrets -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' | grep -q "plue-eso@"; then
  echo -e "Checking: Workload Identity annotation... ${GREEN}✓${NC}"
  ((CHECKS_PASSED++))
else
  echo -e "Checking: Workload Identity annotation... ${RED}✗${NC}"
  echo "  Expected annotation: iam.gke.io/gcp-service-account"
  ((CHECKS_FAILED++))
fi

# -----------------------------------------------------------------------------
# Check 4: CRDs Installed
# -----------------------------------------------------------------------------

check "ClusterSecretStore CRD exists" \
  "kubectl get crd clustersecretstores.external-secrets.io"

check "ExternalSecret CRD exists" \
  "kubectl get crd externalsecrets.external-secrets.io"

# -----------------------------------------------------------------------------
# Check 5: ClusterSecretStore
# -----------------------------------------------------------------------------

if check "ClusterSecretStore 'gcpsm-secret-store' exists" \
  "kubectl get clustersecretstore gcpsm-secret-store"; then

  # Check status
  status=$(kubectl get clustersecretstore gcpsm-secret-store -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
  if [ "$status" = "True" ]; then
    echo -e "  Status: ${GREEN}Ready${NC}"
  else
    echo -e "  Status: ${YELLOW}$status${NC}"
    echo "  Run: kubectl describe clustersecretstore gcpsm-secret-store"
  fi
fi

# -----------------------------------------------------------------------------
# Check 6: ExternalSecrets
# -----------------------------------------------------------------------------

check_with_output "ExternalSecrets in 'plue' namespace" \
  "kubectl get externalsecrets -n plue 2>/dev/null || echo 'No ExternalSecrets found'"

# Check database credentials ExternalSecret
if kubectl get externalsecret database-credentials -n plue >/dev/null 2>&1; then
  status=$(kubectl get externalsecret database-credentials -n plue -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  if [ "$status" = "True" ]; then
    echo -e "  database-credentials: ${GREEN}Ready${NC}"
    ((CHECKS_PASSED++))
  else
    echo -e "  database-credentials: ${RED}Not Ready${NC}"
    ((CHECKS_FAILED++))
    kubectl describe externalsecret database-credentials -n plue | grep -A 5 "Events:"
  fi
fi

# Check API secrets ExternalSecret
if kubectl get externalsecret api-secrets -n plue >/dev/null 2>&1; then
  status=$(kubectl get externalsecret api-secrets -n plue -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  if [ "$status" = "True" ]; then
    echo -e "  api-secrets: ${GREEN}Ready${NC}"
    ((CHECKS_PASSED++))
  else
    echo -e "  api-secrets: ${RED}Not Ready${NC}"
    ((CHECKS_FAILED++))
    kubectl describe externalsecret api-secrets -n plue | grep -A 5 "Events:"
  fi
fi

# -----------------------------------------------------------------------------
# Check 7: Kubernetes Secrets Created
# -----------------------------------------------------------------------------

check "K8s Secret 'plue-database' exists" \
  "kubectl get secret plue-database -n plue"

check "K8s Secret 'plue-api-secrets' exists" \
  "kubectl get secret plue-api-secrets -n plue"

# Verify secret has expected keys
if kubectl get secret plue-database -n plue >/dev/null 2>&1; then
  keys=$(kubectl get secret plue-database -n plue -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')
  echo "  Keys in plue-database: $keys"
fi

if kubectl get secret plue-api-secrets -n plue >/dev/null 2>&1; then
  keys=$(kubectl get secret plue-api-secrets -n plue -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')
  echo "  Keys in plue-api-secrets: $keys"
fi

# -----------------------------------------------------------------------------
# Check 8: ESO Controller Logs (recent errors)
# -----------------------------------------------------------------------------

echo ""
echo "Recent ESO controller logs (errors only):"
kubectl logs -n external-secrets deployment/external-secrets --tail=50 | grep -i error || echo "  No errors found"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "==================================================================="
echo "Verification Summary"
echo "==================================================================="
echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed!${NC}"
  echo ""
  echo "External Secrets Operator is correctly configured."
  echo ""
  echo "Next steps:"
  echo "1. Verify pods can access secrets:"
  echo "   kubectl get pods -n plue"
  echo "   kubectl exec -n plue deployment/api -- env | grep -E '(DATABASE|ANTHROPIC|JWT|SESSION)'"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Some checks failed${NC}"
  echo ""
  echo "Troubleshooting commands:"
  echo "  kubectl logs -n external-secrets deployment/external-secrets -f"
  echo "  kubectl describe clustersecretstore gcpsm-secret-store"
  echo "  kubectl describe externalsecret database-credentials -n plue"
  echo "  kubectl describe externalsecret api-secrets -n plue"
  echo ""
  exit 1
fi
