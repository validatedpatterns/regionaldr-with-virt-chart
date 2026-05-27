# Fix `edge-gitops-vms-deploy.sh` in regionaldr-with-virt-chart

Handoff spec for an implementing agent. Apply changes in the **regionaldr-with-virt-chart** repository, not in ramendr-techdemo.

## Target repository and file

| Item | Value |
|------|-------|
| Repo | `https://github.com/validatedpatterns/regionaldr-with-virt-chart` |
| File to edit | `ansible/roles/edge_gitops_vms_deploy/files/edge-gitops-vms-deploy.sh` |
| Related (no change required) | `templates/job-edge-gitops-vms-deploy.yaml`, `ansible/roles/edge_gitops_vms_deploy/tasks/main.yml` |

The PostSync job passes pattern values via ConfigMap key `values-egv-dr.yaml` (full merged `.Values` from Argo) and sets `HELM_CHART_VERSION` from `edgeGitopsVms.chartVersion`. The script renders `edge-gitops-vms` and applies manifests on the **placement target spoke only** (same as today).

## Problem summary

Windows VMs fail with `datasources.cdi.kubevirt.io "windows2k22" not found` even when pattern values define `externalDataSources.windows2k22` and the edge-gitops-vms chart (≥ 0.3.5) renders the correct manifests.

**Root cause is the deploy script, not the chart version.** The script:

1. **Step 3b** exits successfully without applying anything if *any* VM/Service/Route/ExternalSecret already exists on primary or secondary (e.g. Redis deploys first → job skips → os-images never created on the target spoke).
2. **Step 4/5** only tracks VM/Service/Route/ExternalSecret in `gitops-vms`; ignores `DataVolume` and `DataSource` in `openshift-virtualization-os-images`, so it can exit with “all resources already exist” while os-images are missing.
3. Existence checks ignore the namespace from the manifest and always query `gitops-vms`.
4. Step 5 applies the full template with `oc apply -n gitops-vms`, which makes os-images apply easy to miss in skip/verify logic even though individual objects may carry their own namespace.

## Expected behavior after fix

**Scope: placement target spoke only.** Do not add logic to deploy os-images or workloads on the other spoke.

On every job run against `$TARGET_CLUSTER`:

1. Render helm template (unchanged).
2. Split output into os-images and workload manifests.
3. **Remove** Step 3b global skip (no `exit 0` because Redis exists on either cluster).
4. On the placement target only: ensure `openshift-virtualization-os-images` exists, apply os-images manifest, then apply workload manifest when workload resources are missing.
5. Verify os-images and workload resources on the target spoke.

## Resources the chart renders (reference)

With `values-egv-dr.yaml` from ramendr-techdemo and chart ≥ 0.3.5:

| Slice | Kinds | Namespace |
|-------|-------|-----------|
| **os-images** | `DataVolume`, `DataSource`, registry `ExternalSecret`, `ClusterRole`, `ClusterRoleBinding` | `openshift-virtualization-os-images` (+ cluster-scoped) |
| **workload** | `VirtualMachine`, `Service`, `Route`, cloud-init/SSH `ExternalSecret` | `gitops-vms` (via `--set namespace=gitops-vms` or manifest default) |

Example os-images objects: `DataVolume/windows2k22`, `DataSource/windows2k22`, `ExternalSecret/es-registry-creds-windows`.

## Implementation changes

### 1. Add constant after `VM_NAMESPACE` (≈ line 33)

```bash
OS_IMAGES_NAMESPACE="${OS_IMAGES_NAMESPACE:-openshift-virtualization-os-images}"
```

### 2. Add manifest split helper (after helper functions, before Step 1)

Add function `split_helm_manifests` that takes rendered YAML and writes two files:

- `$WORK_DIR/os-images-manifest.yaml` — os-images slice
- `$WORK_DIR/workload-manifest.yaml` — everything else

Use Python (already required for YAML validation in the script):

```bash
split_helm_manifests() {
  local input="$1"
  local os_images_out="$2"
  local workload_out="$3"
  python3 - "$input" "$os_images_out" "$workload_out" "$OS_IMAGES_NAMESPACE" <<'PY'
import sys, yaml

input_path, os_out, wl_out, os_ns = sys.argv[1:5]
os_docs, wl_docs = [], []

with open(input_path, encoding="utf-8") as fh:
    for doc in yaml.safe_load_all(fh):
        if not doc:
            continue
        kind = doc.get("kind", "")
        meta = doc.get("metadata") or {}
        ns = meta.get("namespace", "")
        name = meta.get("name", "")

        if kind in ("DataVolume", "DataSource") and ns == os_ns:
            os_docs.append(doc)
        elif kind == "ExternalSecret" and ns == os_ns:
            os_docs.append(doc)
        elif kind in ("ClusterRole", "ClusterRoleBinding") and "os-images.kubevirt.io" in name:
            os_docs.append(doc)
        else:
            wl_docs.append(doc)

def write(path, docs):
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump_all(docs, fh, default_flow_style=False)

write(os_out, os_docs)
write(wl_out, wl_docs)
PY
}
```

Add function `apply_os_images_on_target` (uses current `KUBECONFIG` — target spoke only):

```bash
apply_os_images_on_target() {
  local manifest="$WORK_DIR/os-images-manifest.yaml"

  if [[ ! -s "$manifest" ]]; then
    echo "  No os-images manifest to apply (empty or missing)"
    return 0
  fi

  echo "  Ensuring namespace $OS_IMAGES_NAMESPACE exists on target cluster..."
  oc create namespace "$OS_IMAGES_NAMESPACE" --dry-run=client -o yaml | oc apply -f -

  echo "  Applying os-images manifest on target cluster (namespace: $OS_IMAGES_NAMESPACE)..."
  if ! oc apply -f "$manifest"; then
    echo "  ❌ Error: Failed to apply os-images manifest on target cluster"
    return 1
  fi
  echo "  ✅ os-images manifest applied on target cluster"
  return 0
}
```

### 3. Call split after Step 2 helm render succeeds (after line ≈261)

After `$WORK_DIR/helm-output.yaml` is written:

```bash
echo ""
echo "Step 2b: Splitting helm output into os-images and workload manifests..."
split_helm_manifests "$WORK_DIR/helm-output.yaml" \
  "$WORK_DIR/os-images-manifest.yaml" \
  "$WORK_DIR/workload-manifest.yaml"
echo "  os-images manifest: $(grep -c '^kind:' "$WORK_DIR/os-images-manifest.yaml" 2>/dev/null || echo 0) resources"
echo "  workload manifest: $(grep -c '^kind:' "$WORK_DIR/workload-manifest.yaml" 2>/dev/null || echo 0) resources"
```

### 4. Remove Step 3b entirely (lines ≈369–391)

**Delete** the block that:

- Loops `$PRIMARY_CLUSTER` and `$SECONDARY_CLUSTER`
- Sets `RESOURCES_FOUND_ON_OTHER_CLUSTER`
- Exits 0 with “Skipping deployment to avoid race conditions”

Also delete `any_resource_exists_on_cluster` if it becomes unused after this removal.

**Do not** replace Step 3b with apply logic on both spokes. The script continues to operate exclusively on the placement target spoke after kubeconfig is obtained (existing Step 4+ flow).

Optional future guard (not required for this fix): on the **target** cluster only, skip workload apply only when **all** workload resources from the manifest already exist — never skip because a subset (e.g. Redis) exists.

### 5. Fix Step 3 resource extraction and list building

Update Step 3 header/log message to mention DataVolume and DataSource where relevant.

Build **`$WORK_DIR/workload-resources-list.txt`** from `workload-manifest.yaml` only (recommended), containing `VirtualMachine`, `Service`, `Route`, and gitops-vms `ExternalSecret` entries with correct namespaces.

If extending the existing awk on full helm output, include `DataVolume` and `DataSource` for completeness but use the workload list alone for Step 4 skip/apply decisions:

```awk
if (resource ~ /^kind: (VirtualMachine|Service|Route|ExternalSecret|DataVolume|DataSource)$/) {
```

When printing list entries, if `namespace` is empty and kind is workload (not DataVolume/DataSource), default to `gitops-vms`:

```awk
if (namespace == "" && kind !~ /DataVolume|DataSource/) {
  namespace = "gitops-vms"
}
```

### 6. Fix Step 4 existence checks (lines ≈433–447)

Use `$WORK_DIR/workload-resources-list.txt` for workload existence checks on the target cluster.

Replace hardcoded namespace:

```bash
# BEFORE (wrong)
check_namespace="$VM_NAMESPACE"

# AFTER
check_namespace="${namespace:-$VM_NAMESPACE}"
```

**Additionally**, before deciding Step 5 can skip, check os-images objects on the target cluster (using `os-images-manifest.yaml` or a small helper). If any os-images resource is missing, do **not** take the “all resources already exist” early exit — proceed to Step 5 apply.

Example check (after target kubeconfig is active):

```bash
OS_IMAGES_COMPLETE=true
# Parse os-images-manifest.yaml for DataVolume/DataSource/ExternalSecret names+namespaces
# If any missing on target → OS_IMAGES_COMPLETE=false
```

Step 5 early exit (`ALL_EXIST == true`) must require **both** `OS_IMAGES_COMPLETE` and all workload resources present.

### 7. Fix Step 5 apply (lines ≈472–608)

Re-render with namespace override (keep existing behavior):

```bash
helm template edge-gitops-vms "$HELM_CHART_URL" $VALUES_ARG --set namespace="$VM_NAMESPACE" \
  > "$TEMPLATE_OUTPUT_FILE" 2>"$TEMPLATE_STDERR_FILE"
```

Split again:

```bash
split_helm_manifests "$TEMPLATE_OUTPUT_FILE" \
  "$WORK_DIR/os-images-manifest.yaml" \
  "$WORK_DIR/workload-manifest.yaml"
```

On the **target cluster only** (existing `KUBECONFIG` / target kubeconfig checks unchanged):

**First** apply os-images:

```bash
apply_os_images_on_target || exit 1
```

**Then** apply workload (when Step 4 found missing workload resources, or always idempotically):

```bash
echo "  Executing: oc apply -n $VM_NAMESPACE -f $WORK_DIR/workload-manifest.yaml"
oc apply -n "$VM_NAMESPACE" -f "$WORK_DIR/workload-manifest.yaml" \
  >"$APPLY_STDOUT_FILE" 2>"$APPLY_STDERR_FILE"
```

Do **not** apply the full combined template with `oc apply -n gitops-vms -f $TEMPLATE_OUTPUT_FILE`.

Os-images apply uses `oc apply -f` (no `-n`) so explicit `metadata.namespace` and cluster-scoped RBAC are handled correctly.

Update success message: “os-images and workload manifests applied on target cluster $TARGET_CLUSTER”.

### 8. Fix Step 6 verification (lines ≈706–726)

On the **target cluster only**, verify:

- Os-images: each `DataVolume`, `DataSource`, and registry `ExternalSecret` from `os-images-manifest.yaml`
- Workload: each entry in `workload-resources-list.txt` using `${namespace:-$VM_NAMESPACE}`

```bash
echo "Step 6: Verifying os-images and workload resources on target cluster ($TARGET_CLUSTER)..."
# os-images checks in $OS_IMAGES_NAMESPACE
# workload checks per workload-resources-list.txt
```

### 9. Update script header comment (line ≈26)

```bash
echo "This job will deploy os-images and workload VMs to the placement target spoke"
```

## Flow after changes

```
Step 2:   helm template → helm-output.yaml
Step 2b:  split → os-images-manifest.yaml + workload-manifest.yaml
          (Step 3b removed — no global skip)
Step 4:   get target kubeconfig; check os-images + workload on TARGET only
Step 5:   if anything missing on TARGET:
            re-render → split
            oc apply os-images-manifest on TARGET
            oc apply workload-manifest on TARGET (-n gitops-vms)
Step 6:   verify os-images + workload on TARGET
```

## Test plan

### Local (no cluster)

```bash
curl -fsSL -o /tmp/egv-0.3.5.tgz \
  "https://github.com/validatedpatterns/helm-charts/releases/download/main/edge-gitops-vms-0.3.5.tgz"

helm template edge-gitops-vms /tmp/egv-0.3.5.tgz \
  -f /path/to/ramendr-techdemo/overrides/values-egv-dr.yaml \
  --set namespace=gitops-vms > /tmp/helm-output.yaml

# Run split_helm_manifests logic; confirm:
# os-images-manifest contains: DataVolume/windows2k22, DataSource/windows2k22,
#   ExternalSecret/es-registry-creds-windows, ClusterRole(os-images...)
# workload-manifest contains: VirtualMachine (redis + desktop), Services, VM ExternalSecrets
# workload-manifest does NOT contain os-images objects
```

### On hub cluster (after deploy)

```bash
oc logs -n open-cluster-management job/edge-gitops-vms-deploy --tail=300
```

Confirm logs show:

- **No** `Skipping deployment to avoid race conditions` when only Redis exists
- `Applying os-images manifest on target cluster` before workload apply
- All apply/verify actions reference `$TARGET_CLUSTER` only (not a loop over primary + secondary)

### On placement target spoke

```bash
oc get dv,datasource,externalsecret -n openshift-virtualization-os-images | grep -i windows
oc get vm -n gitops-vms
```

Target spoke should have `windows2k22` DV and DataSource plus `windows2k22-desktop-001` VM.

### Regression: Redis-only first deploy

1. Deploy with only `vms.redis` in values (or delete desktop VM).
2. Re-run job after adding desktop VM to values.
3. Confirm os-images and desktop VM are created on the target spoke (job must not skip at Step 3b).

## Out of scope

- **Other spoke:** Do not apply os-images or workloads on the non-target spoke. DR replication handles cross-spoke data separately.
- **CDI VolumePopulator:** If `windows2k22` DataSource exists and is Ready but the desktop clone PVC fails with `UnrecognizedDataSourceKind` / `storage.usePopulator`, that is a separate OCP 4.20+ CDI issue.

## Constraints for implementing agent

- Edit **only** `edge-gitops-vms-deploy.sh` unless a tiny helper is needed elsewhere.
- Preserve existing error handling, kubeconfig retrieval, hub-vs-spoke safety checks, and YAML validation.
- Keep deployment **single-spoke** (placement target only); do not add primary+secondary apply loops.
- Keep `set -euo pipefail`; use `set +e` / `set -e` around oc apply capture blocks as today.
- Do not change chart version wiring or Argo job template unless strictly necessary.
- Match existing bash style (echo prefixes, emoji markers optional but consistent with file).
- Run `shellcheck` on the script if available.

## Acceptance criteria

- [ ] Step 3b global skip removed (no early exit when Redis exists on either cluster).
- [ ] Manifest split separates os-images from workload.
- [ ] Os-images manifest applied on **placement target only** before workload apply.
- [ ] Workload apply uses `workload-manifest.yaml` on placement target only.
- [ ] Existence checks use manifest namespace, not hardcoded `gitops-vms` for all kinds.
- [ ] Step 5 does not skip when workload exists but os-images (`windows2k22`) are missing on target.
- [ ] **No** new logic deploys resources on the non-target spoke.
