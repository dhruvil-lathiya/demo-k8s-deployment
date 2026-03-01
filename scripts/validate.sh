#!/bin/bash
# ============================================================
# validate.sh - Deployment Health Validation Script
#
# Checks:
#   1. Rollout status completed
#   2. All replicas are Ready
#   3. No pods in CrashLoopBackOff
#   4. Pod restart count warnings
#   5. Running image versions
#
# Usage: ./scripts/validate.sh [deployment-name] [namespace]
# Exit:  0 = healthy | 1 = unhealthy
# ============================================================

set -euo pipefail

DEPLOYMENT="${1:-demo-k8s-api}"
NAMESPACE="${2:-default}"
TIMEOUT="${3:-120}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  Deployment Validation: ${DEPLOYMENT}"
echo "  Namespace: ${NAMESPACE}"
echo "  Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================"
echo ""

UNHEALTHY=0

# --- Check 1: Rollout status ---
echo "--- Check 1: Rollout Status ---"
if kubectl rollout status deployment/"${DEPLOYMENT}" \
    -n "${NAMESPACE}" --timeout="${TIMEOUT}s" 2>/dev/null; then
    echo -e "${GREEN}[PASS]${NC} Rollout completed successfully."
else
    echo -e "${RED}[FAIL]${NC} Rollout did not complete within ${TIMEOUT}s."
    UNHEALTHY=1
fi
echo ""

# --- Check 2: All replicas Ready ---
echo "--- Check 2: Replica Readiness ---"
DESIRED=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}')
READY=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}')
READY="${READY:-0}"

echo "  Desired: ${DESIRED} | Ready: ${READY}"
if [[ "${READY}" -eq "${DESIRED}" ]]; then
    echo -e "${GREEN}[PASS]${NC} All ${DESIRED} replicas are Ready."
else
    echo -e "${RED}[FAIL]${NC} Only ${READY}/${DESIRED} replicas are Ready."
    UNHEALTHY=1
fi
echo ""

# --- Check 3: CrashLoopBackOff detection ---
echo "--- Check 3: CrashLoopBackOff Detection ---"
CRASH_PODS=$(kubectl get pods -n "${NAMESPACE}" \
    -l app="${DEPLOYMENT}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' 2>/dev/null \
    | grep -i "CrashLoopBackOff" || true)

if [[ -n "${CRASH_PODS}" ]]; then
    echo -e "${RED}[FAIL]${NC} Pods in CrashLoopBackOff:"
    echo "${CRASH_PODS}"
    UNHEALTHY=1
else
    echo -e "${GREEN}[PASS]${NC} No pods in CrashLoopBackOff."
fi
echo ""

# --- Check 4: Restart count ---
echo "--- Check 4: Pod Restart Count ---"
HIGH_RESTARTS=$(kubectl get pods -n "${NAMESPACE}" \
    -l app="${DEPLOYMENT}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{end}' 2>/dev/null \
    | awk -F'\t' '$2 > 3 {print $0}' || true)

if [[ -n "${HIGH_RESTARTS}" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Pods with high restart counts (>3):"
    echo "${HIGH_RESTARTS}"
else
    echo -e "${GREEN}[PASS]${NC} Restart counts are normal."
fi
echo ""

# --- Check 5: Running image versions ---
echo "--- Check 5: Running Image Versions ---"
kubectl get pods -n "${NAMESPACE}" \
    -l app="${DEPLOYMENT}" \
    -o jsonpath='{range .items[*]}  {.metadata.name}: {.spec.containers[0].image}{"\n"}{end}'
echo ""

# --- Summary ---
echo "============================================"
if [[ "${UNHEALTHY}" -eq 0 ]]; then
    echo -e "  Result: ${GREEN}HEALTHY${NC}"
    echo "============================================"
    exit 0
else
    echo -e "  Result: ${RED}UNHEALTHY${NC} — Issues detected above."
    echo "============================================"
    exit 1
fi