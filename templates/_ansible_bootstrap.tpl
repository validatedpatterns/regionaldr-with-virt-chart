{{/*
  Expand on-cluster: stage ConfigMap flat keys into a tree under /tmp/regionaldr-ansible,
  install ansible-core, run from that directory.
*/}}
{{- define "rdr.ansibleBootstrap" -}}
set -euo pipefail
export HOME=/tmp
export ANSIBLE_LOCAL_TMP=/tmp/ansible-tmp
STAGE=/tmp/regionaldr-ansible
rm -rf "$STAGE"
mkdir -p "$STAGE"
shopt -s nullglob
for f in /ansible-cm/*; do
  [[ -f "$f" ]] || continue
  key=$(basename "$f")
  rel=${key//__//}
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp "$f" "$STAGE/$rel"
done
export PATH="/tmp/.local/bin:$PATH"
cd "$STAGE"
{{- end }}
