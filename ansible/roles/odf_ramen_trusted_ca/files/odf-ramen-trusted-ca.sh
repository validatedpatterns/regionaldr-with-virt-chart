#!/usr/bin/env bash
# After MirrorPeer (and policies that populate cluster-proxy-ca-bundle), copy CA from the hub
# cluster-proxy-ca-bundle ConfigMap — do not re-extract from router/spoke API servers.
# Wait until Ramen hub config has s3StoreProfiles (from ODF/MirrorPeer), then patch caCertificates only.
set -euo pipefail

PRIMARY_CLUSTER="${PRIMARY_CLUSTER:?PRIMARY_CLUSTER is required}"
SECONDARY_CLUSTER="${SECONDARY_CLUSTER:?SECONDARY_CLUSTER is required}"
WORK_DIR="${WORK_DIR:-/tmp/odf-ssl-certs}"
RAMEN_CM_WAIT_SECONDS="${RAMEN_CM_WAIT_SECONDS:-3600}"
TRUSTED_CA_WAIT_SECONDS="${TRUSTED_CA_WAIT_SECONDS:-3600}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAMEN_SCRIPT="${SCRIPT_DIR}/odf-ssl-ramen-hub-configmap.sh"

die() {
  echo "❌ odf-ramen-trusted-ca.sh: $*" >&2
  exit 1
}

command -v oc >/dev/null 2>&1 || die "oc not found"
[[ -x "$RAMEN_SCRIPT" ]] || [[ -f "$RAMEN_SCRIPT" ]] || die "missing $RAMEN_SCRIPT"
chmod +x "$RAMEN_SCRIPT" 2>/dev/null || true

mkdir -p "$WORK_DIR"

wait_for_trusted_ca() {
  local deadline=$((SECONDS + TRUSTED_CA_WAIT_SECONDS))
  echo "Waiting for cluster-proxy-ca-bundle (openshift-config) with non-trivial ca-bundle.crt (max ${TRUSTED_CA_WAIT_SECONDS}s)..."
  while ((SECONDS < deadline)); do
    local data bytes
    data=$(oc get configmap cluster-proxy-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null || true)
    bytes=$(printf '%s' "$data" | wc -c | tr -d ' ')
    if [[ "${bytes:-0}" -ge 64 ]]; then
      printf '%s' "$data" >"$WORK_DIR/combined-ca-bundle.crt"
      echo "  ✅ trusted CA bundle captured (${bytes} bytes)"
      return 0
    fi
    echo "  ... ca-bundle.crt bytes=${bytes:-0}, retry in ${POLL_INTERVAL}s"
    sleep "$POLL_INTERVAL"
  done
  die "cluster-proxy-ca-bundle not ready in time — ensure ACM/ODF policy populated it (see opp-policy-chart policy-odf-managed-cluster-ssl)"
}

count_s3_profiles() {
  local yaml="$1"
  [[ -n "$yaml" ]] || {
    echo 0
    return
  }
  if command -v yq &>/dev/null; then
    local k t
    k=$(echo "$yaml" | yq eval '.kubeObjectProtection.s3StoreProfiles | length' 2>/dev/null | tr -d ' \n\r' || echo 0)
    t=$(echo "$yaml" | yq eval '.s3StoreProfiles | length' 2>/dev/null | tr -d ' \n\r' || echo 0)
    k=$((10#${k:-0}))
    t=$((10#${t:-0}))
    echo $((k > t ? k : t))
  else
    echo "$yaml" | grep -c 's3ProfileName:' 2>/dev/null || echo 0
  fi
}

wait_for_ramen_s3_profiles() {
  local deadline=$((SECONDS + RAMEN_CM_WAIT_SECONDS)) yaml c
  echo "Waiting for ramen-hub-operator-config s3StoreProfiles (openshift-operators, max ${RAMEN_CM_WAIT_SECONDS}s)..."
  while ((SECONDS < deadline)); do
    yaml=$(oc get configmap ramen-hub-operator-config -n openshift-operators -o jsonpath='{.data.ramen_manager_config\.yaml}' 2>/dev/null || true)
    if [[ -n "$yaml" ]] && echo "$yaml" | grep -q 's3StoreProfiles'; then
      c=$(count_s3_profiles "$yaml")
      if [[ "${c:-0}" -ge 2 ]]; then
        echo "  ✅ ramen_manager_config has s3StoreProfiles (count≈$c)"
        return 0
      fi
    fi
    echo "  ... profiles not ready yet (need >=2), retry in ${POLL_INTERVAL}s"
    sleep "$POLL_INTERVAL"
  done
  die "ramen-hub-operator-config never gained s3StoreProfiles — confirm MirrorPeer and hub Ramen operator reconciled"
}

wait_for_trusted_ca
wait_for_ramen_s3_profiles

export WORK_DIR PRIMARY_CLUSTER SECONDARY_CLUSTER
exec bash "$RAMEN_SCRIPT"
