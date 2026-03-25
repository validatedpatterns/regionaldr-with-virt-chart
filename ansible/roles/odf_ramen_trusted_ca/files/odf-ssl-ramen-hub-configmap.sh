#!/usr/bin/env bash
# Update ramen-hub-operator-config with caCertificates in s3StoreProfiles (same logic path as
# odf-ssl-certificate-extraction.sh §7b). Invoked by the Ansible extraction playbook so behavior
# matches the proven shell implementation.
set -euo pipefail

WORK_DIR="${WORK_DIR:-/tmp/odf-ssl-certs}"
PRIMARY_CLUSTER="${PRIMARY_CLUSTER:?PRIMARY_CLUSTER is required}"
SECONDARY_CLUSTER="${SECONDARY_CLUSTER:?SECONDARY_CLUSTER is required}"

die() { echo "❌ odf-ssl-ramen-hub-configmap.sh: $*" >&2; exit 1; }

trap 'ec=$?; echo "❌ odf-ssl-ramen-hub-configmap.sh: command failed (exit $ec) at line $LINENO — see stderr above for the failing command." >&2' ERR

mkdir -p "$WORK_DIR"
[[ -f "$WORK_DIR/combined-ca-bundle.crt" ]] || die "missing $WORK_DIR/combined-ca-bundle.crt"

echo "7b. Updating ramen-hub-operator-config in openshift-operators namespace (bash parity script)..."

CA_BUNDLE_BASE64=$(base64 -w 0 < "$WORK_DIR/combined-ca-bundle.crt" 2>/dev/null || base64 < "$WORK_DIR/combined-ca-bundle.crt" | tr -d '\n')

# Post-apply: fetch live YAML to disk (no huge shell vars) and validate structure.
verify_post_apply() {
  local f="$WORK_DIR/.ramen-post-apply-verify.yaml" attempt
  local MIN_REQUIRED_PROFILES=2
  local PK PT CK CT bad maxp
  local last_PK=0 last_PT=0 last_CK=0 last_CT=0 last_maxp=0 last_bad=1 oc_ok=0
  for attempt in $(seq 1 10); do
    if [[ "$attempt" -gt 1 ]]; then
      sleep 6
    else
      sleep 2
    fi
    if oc get configmap ramen-hub-operator-config -n openshift-operators \
      -o jsonpath='{.data.ramen_manager_config\.yaml}' > "$f" 2>/dev/null; then
      oc_ok=1
    else
      oc_ok=0
      continue
    fi
    [[ -s "$f" ]] || continue
    grep -q 'caCertificates' "$f" || continue
    grep -q 's3StoreProfiles' "$f" || continue
    PK=$(yq eval '(.kubeObjectProtection.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' | head -1 || echo 0)
    PT=$(yq eval '(.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' | head -1 || echo 0)
    CK=$(yq eval '[(.kubeObjectProtection.s3StoreProfiles // [])[]? | select(has("caCertificates"))] | length' "$f" 2>/dev/null | tr -d ' \n\r' | head -1 || echo 0)
    CT=$(yq eval '[(.s3StoreProfiles // [])[]? | select(has("caCertificates"))] | length' "$f" 2>/dev/null | tr -d ' \n\r' | head -1 || echo 0)
    [[ "$PK" =~ ^[0-9]+$ ]] || PK=0
    [[ "$PT" =~ ^[0-9]+$ ]] || PT=0
    [[ "$CK" =~ ^[0-9]+$ ]] || CK=0
    [[ "$CT" =~ ^[0-9]+$ ]] || CT=0
    bad=0
    [[ "$PK" -gt 0 && "$CK" -lt "$PK" ]] && bad=1
    [[ "$PT" -gt 0 && "$CT" -lt "$PT" ]] && bad=1
    maxp=$(( PK > PT ? PK : PT ))
    last_PK=$PK
    last_PT=$PT
    last_CK=$CK
    last_CT=$CT
    last_maxp=$maxp
    last_bad=$bad
    [[ "$bad" -eq 1 ]] && continue
    [[ "$maxp" -ge "$MIN_REQUIRED_PROFILES" ]] || continue
    [[ "$CK" -ge "$MIN_REQUIRED_PROFILES" || "$CT" -ge "$MIN_REQUIRED_PROFILES" ]] || continue
    echo "  ✅ ramen-hub-operator-config verified (attempt $attempt): kubeObjectProtection s3 profiles $PK/$CK, top-level $PT/$CT"
    return 0
  done
  echo "  ❌ Post-apply verification failed after 10 attempts." >&2
  echo "  ❌ Diagnosis: oc_get_ok=$oc_ok last_kop_profiles=$last_PK last_kop_with_ca=$last_CK last_top_profiles=$last_PT last_top_with_ca=$last_CT last_max_profiles=$last_maxp last_section_bad=$last_bad (need each non-empty section fully CA-populated; max profiles >= $MIN_REQUIRED_PROFILES; at least $MIN_REQUIRED_PROFILES with CA in kop OR top)" >&2
  echo "  ❌ If kop/top counts are 0, the hub operator may have removed ramen_manager_config data or the key is empty." >&2
  [[ -f "$f" ]] && { echo "  ❌ First 80 lines of live ramen_manager_config from cluster:" >&2; head -n 80 "$f" >&2; } || echo "  ❌ No verify file (oc get may have failed every attempt)." >&2
  return 1
}

UPDATED_YAML=""

if oc get configmap ramen-hub-operator-config -n openshift-operators &>/dev/null; then
  echo "  ConfigMap exists, updating ramen_manager_config.yaml with caCertificates in s3StoreProfiles..."

  EXISTING_YAML=$(oc get configmap ramen-hub-operator-config -n openshift-operators -o jsonpath='{.data.ramen_manager_config\.yaml}' 2>/dev/null || echo "")

  MIN_REQUIRED_PROFILES=2
  if [[ -n "$EXISTING_YAML" ]]; then
    if command -v yq &>/dev/null; then
      COUNT_KOP=$(echo "$EXISTING_YAML" | yq eval '.kubeObjectProtection.s3StoreProfiles | length' 2>/dev/null | tr -d ' \n\r' | head -1 || echo "0")
      COUNT_TOP=$(echo "$EXISTING_YAML" | yq eval '.s3StoreProfiles | length' 2>/dev/null | tr -d ' \n\r' | head -1 || echo "0")
      COUNT_KOP=$((10#${COUNT_KOP:-0}))
      COUNT_TOP=$((10#${COUNT_TOP:-0}))
      EXISTING_PROFILE_COUNT=$(( COUNT_KOP >= COUNT_TOP ? COUNT_KOP : COUNT_TOP ))
    else
      EXISTING_PROFILE_COUNT=$(echo "$EXISTING_YAML" | grep -c "s3ProfileName:" 2>/dev/null || echo "0")
      if [[ $EXISTING_PROFILE_COUNT -eq 0 ]]; then
        EXISTING_PROFILE_COUNT=$(echo "$EXISTING_YAML" | grep -c "s3Bucket:" 2>/dev/null || echo "0")
      fi
    fi
    EXISTING_PROFILE_COUNT=$(echo "$EXISTING_PROFILE_COUNT" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")
    EXISTING_PROFILE_COUNT=$((10#$EXISTING_PROFILE_COUNT))
    if [[ $EXISTING_PROFILE_COUNT -lt $MIN_REQUIRED_PROFILES ]]; then
      echo "  ❌ CRITICAL: Insufficient s3StoreProfiles in existing ConfigMap (found $EXISTING_PROFILE_COUNT, need $MIN_REQUIRED_PROFILES)"
      echo "$EXISTING_YAML" | head -n 50
      die "Insufficient s3StoreProfiles — pre-create profiles in ramen-hub-operator-config or use the full extraction job on the hub"
    fi
    echo "  ✅ Found $EXISTING_PROFILE_COUNT s3StoreProfiles (patching caCertificates only)"
  fi

  PATCHED_VIA_YQ=false
  if [[ -n "$EXISTING_YAML" ]]; then
    echo "$EXISTING_YAML" > "$WORK_DIR/existing-ramen-config.yaml"
    if ! command -v yq &>/dev/null; then
      die "yq is required (e.g. mikefarah/yq v4)"
    fi
    export CA_BUNDLE_BASE64
    YQ_PATCHED=false
    if yq eval -i '.s3StoreProfiles[]? |= . + {"caCertificates": strenv(CA_BUNDLE_BASE64)}' "$WORK_DIR/existing-ramen-config.yaml" 2>/dev/null; then
      YQ_PATCHED=true
    fi
    if yq eval -i '.kubeObjectProtection.s3StoreProfiles[]? |= . + {"caCertificates": strenv(CA_BUNDLE_BASE64)}' "$WORK_DIR/existing-ramen-config.yaml" 2>/dev/null; then
      YQ_PATCHED=true
    fi
    if [[ "$YQ_PATCHED" != "true" ]]; then
      die "yq could not patch s3StoreProfiles (check kubeObjectProtection / top-level s3StoreProfiles). yq: $(yq --version 2>/dev/null || true)"
    fi
    grep -q "caCertificates" "$WORK_DIR/existing-ramen-config.yaml" || die "patched file has no caCertificates"
    cp "$WORK_DIR/existing-ramen-config.yaml" "$WORK_DIR/ramen_manager_config.yaml"
    PATCHED_VIA_YQ=true
  else
    UPDATED_YAML="kubeObjectProtection:
  s3StoreProfiles:
  - s3ProfileName: $PRIMARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
  - s3ProfileName: $SECONDARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
s3StoreProfiles:
  - s3ProfileName: $PRIMARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
  - s3ProfileName: $SECONDARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\""
  fi

  if [[ "$PATCHED_VIA_YQ" != "true" ]]; then
    echo "$UPDATED_YAML" > "$WORK_DIR/ramen_manager_config.yaml"
  fi

  echo "  Building ConfigMap manifest (literal block) and oc apply..."
  oc get configmap ramen-hub-operator-config -n openshift-operators -o yaml > "$WORK_DIR/ramen-configmap-template.yaml" 2>/dev/null || true

  UPDATE_EXIT_CODE=1
  UPDATE_OUTPUT=""
  if [[ -f "$WORK_DIR/ramen-configmap-template.yaml" ]]; then
    {
      echo "apiVersion: v1"
      echo "kind: ConfigMap"
      echo "metadata:"
      echo "  name: ramen-hub-operator-config"
      echo "  namespace: openshift-operators"
      echo "data:"
      echo "  ramen_manager_config.yaml: |"
      sed 's/^/    /' "$WORK_DIR/ramen_manager_config.yaml"
    } > "$WORK_DIR/ramen-configmap-updated.yaml"
    if UPDATE_OUTPUT=$(oc apply -f "$WORK_DIR/ramen-configmap-updated.yaml" 2>&1); then
      UPDATE_EXIT_CODE=0
    else
      UPDATE_EXIT_CODE=$?
    fi
    rm -f "$WORK_DIR/ramen-configmap-template.yaml" "$WORK_DIR/ramen-configmap-updated.yaml"
  else
    if UPDATE_OUTPUT=$(oc set data configmap/ramen-hub-operator-config -n openshift-operators \
      ramen_manager_config.yaml="$(cat "$WORK_DIR/ramen_manager_config.yaml")" 2>&1); then
      UPDATE_EXIT_CODE=0
    else
      UPDATE_EXIT_CODE=$?
    fi
  fi

  echo "  Update exit code: $UPDATE_EXIT_CODE"
  echo "  Update output: $UPDATE_OUTPUT"

  if [[ $UPDATE_EXIT_CODE -eq 0 ]]; then
    verify_post_apply || die "Post-apply verification failed — CA not present in live ConfigMap"
  else
    die "oc apply/set data failed: $UPDATE_OUTPUT"
  fi

  rm -f "$WORK_DIR/existing-ramen-config.yaml" "$WORK_DIR/ramen_manager_config.yaml" || true
else
  echo "  ConfigMap does not exist; creating ramen-hub-operator-config..."
  oc create configmap ramen-hub-operator-config -n openshift-operators \
    --from-literal=ramen_manager_config.yaml="kubeObjectProtection:
  s3StoreProfiles:
  - s3ProfileName: $PRIMARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
  - s3ProfileName: $SECONDARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
s3StoreProfiles:
  - s3ProfileName: $PRIMARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"
  - s3ProfileName: $SECONDARY_CLUSTER
    caCertificates: \"$CA_BUNDLE_BASE64\"" || die "oc create configmap failed"

  verify_post_apply || die "Post-create verification failed"
fi

echo "  ramen-hub-operator-config updated successfully with base64-encoded CA bundle in s3StoreProfiles"
