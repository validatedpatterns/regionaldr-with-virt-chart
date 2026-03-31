#!/usr/bin/env bash
# Optional: install boutique from https://charts.validatedpatterns.io on the same primary/placement
# target as edge-gitops-vms, using the same pattern values file (-f).
set -euo pipefail

shopt -s nocasematch
case "${BOUTIQUE_DEPLOY:-false}" in
  true|1|yes) ;;
  *)
    echo "Boutique deploy disabled (BOUTIQUE_DEPLOY=${BOUTIQUE_DEPLOY:-false}); skipping."
    exit 0
    ;;
esac
shopt -u nocasematch

PRIMARY_CLUSTER="${PRIMARY_CLUSTER:-ocp-primary}"
SECONDARY_CLUSTER="${SECONDARY_CLUSTER:-ocp-secondary}"
BOUTIQUE_NAMESPACE="${BOUTIQUE_NAMESPACE:-boutique}"
BOUTIQUE_CHART_VERSION="${BOUTIQUE_CHART_VERSION:?BOUTIQUE_CHART_VERSION is required when BOUTIQUE_DEPLOY is true}"
BOUTIQUE_CHART_NAME="${BOUTIQUE_CHART_NAME:-boutique}"
HELM_REPO_URL="${BOUTIQUE_HELM_REPO_URL:-https://charts.validatedpatterns.io}"
HELM_REPO_ALIAS="${BOUTIQUE_HELM_REPO_ALIAS:-validatedpatterns}"
# Same overrides as edge-gitops-vms (mounted ConfigMap in the job pod)
BOUTIQUE_VALUES_FILE="${BOUTIQUE_VALUES_FILE:-/tmp/values/values-egv-dr.yaml}"

DRPC_NAMESPACE="${DRPC_NAMESPACE:-openshift-dr-ops}"
PLACEMENT_NAME="${PLACEMENT_NAME:-gitops-vm-protection-placement-1}"
WORK_DIR="/tmp/boutique-chart-deploy"
mkdir -p "$WORK_DIR"

if [[ ! -f "$BOUTIQUE_VALUES_FILE" ]]; then
  echo "❌ Values file not found: $BOUTIQUE_VALUES_FILE (expected same pattern overrides as edge-gitops-vms)"
  exit 1
fi

get_target_cluster_from_placement() {
  echo "Getting target cluster from Placement: $PLACEMENT_NAME"
  local pd
  pd=$(oc get placementdecision -n "$DRPC_NAMESPACE" \
    -l cluster.open-cluster-management.io/placement="$PLACEMENT_NAME" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "$pd" ]]; then
    echo "  ⚠️  No PlacementDecision; using primary: $PRIMARY_CLUSTER"
    TARGET_CLUSTER="$PRIMARY_CLUSTER"
    return 1
  fi
  TARGET_CLUSTER=$(oc get placementdecision "$pd" -n "$DRPC_NAMESPACE" \
    -o jsonpath='{.status.decisions[0].clusterName}' 2>/dev/null || echo "")
  if [[ -z "$TARGET_CLUSTER" ]]; then
    echo "  ⚠️  Empty decision; using primary: $PRIMARY_CLUSTER"
    TARGET_CLUSTER="$PRIMARY_CLUSTER"
    return 1
  fi
  echo "  ✅ Target cluster from Placement: $TARGET_CLUSTER"
  return 0
}

get_target_cluster_kubeconfig() {
  local cluster="$1"
  echo "Getting kubeconfig for managed cluster: $cluster"
  local secret_names=("${cluster}-admin-kubeconfig" "admin-kubeconfig" "import-kubeconfig")
  local got=false
  for secret_name in "${secret_names[@]}"; do
    if oc get secret "$secret_name" -n "$cluster" -o jsonpath='{.data.kubeconfig}' 2>/dev/null | \
       base64 -d > "$WORK_DIR/target-kubeconfig.yaml" 2>/dev/null && [[ -s "$WORK_DIR/target-kubeconfig.yaml" ]]; then
      got=true
      echo "  ✅ kubeconfig from secret $secret_name"
      break
    fi
  done
  if [[ "$got" != "true" ]]; then
    if oc get secret -n "$cluster" -o name 2>/dev/null | grep -E "(admin-kubeconfig|kubeconfig)" | head -1 | \
       xargs -I {} oc get {} -n "$cluster" -o jsonpath='{.data.kubeconfig}' 2>/dev/null | \
       base64 -d > "$WORK_DIR/target-kubeconfig.yaml" 2>/dev/null && [[ -s "$WORK_DIR/target-kubeconfig.yaml" ]]; then
      got=true
    fi
  fi
  if [[ "$got" == "true" ]]; then
    export KUBECONFIG="$WORK_DIR/target-kubeconfig.yaml"
    if oc get nodes &>/dev/null; then
      echo "  ✅ Connected to cluster $cluster"
      return 0
    fi
  fi
  echo "  ❌ Could not get kubeconfig for $cluster"
  return 1
}

TARGET_CLUSTER="$PRIMARY_CLUSTER"
get_target_cluster_from_placement || true

if ! get_target_cluster_kubeconfig "$TARGET_CLUSTER"; then
  echo "❌ Boutique: need kubeconfig for target $TARGET_CLUSTER"
  exit 1
fi

CURRENT_CLUSTER=$(oc config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "")
if [[ "$CURRENT_CLUSTER" == "in-cluster" || "$CURRENT_CLUSTER" == "local-cluster" ]]; then
  echo "❌ Refusing boutique install on hub context ($CURRENT_CLUSTER)"
  exit 1
fi

echo ""
echo "=== Boutique chart ($BOUTIQUE_CHART_NAME) → cluster $TARGET_CLUSTER namespace $BOUTIQUE_NAMESPACE ==="
echo "    repo: $HELM_REPO_URL"
echo "    version: $BOUTIQUE_CHART_VERSION"
echo "    values: $BOUTIQUE_VALUES_FILE"

cd /tmp || exit 1
export HELM_CACHE_HOME="/tmp/.helm/cache-boutique"
export HELM_CONFIG_HOME="/tmp/.helm/config-boutique"
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME"

if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add "$HELM_REPO_ALIAS" "$HELM_REPO_URL" --force-update
helm repo update

helm upgrade --install "$BOUTIQUE_CHART_NAME" "${HELM_REPO_ALIAS}/${BOUTIQUE_CHART_NAME}" \
  --version "$BOUTIQUE_CHART_VERSION" \
  -f "$BOUTIQUE_VALUES_FILE" \
  -n "$BOUTIQUE_NAMESPACE" \
  --create-namespace

echo "✅ Boutique chart install/upgrade finished."
