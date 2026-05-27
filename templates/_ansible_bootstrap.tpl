{{/*
  Stage ConfigMap flat keys into /tmp/regionaldr-ansible (no ansible install).
  Use for long-running shell prereqs so output streams to pod logs without Ansible buffering.
*/}}
{{- define "rdr.ansibleStageOnly" -}}
set -euo pipefail
export HOME=/tmp
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
cd "$STAGE"
{{- end }}

{{/*
  Stage + pip install ansible-core + PATH. Use when running ansible-playbook.
*/}}
{{- define "rdr.ansibleBootstrap" -}}
{{ include "rdr.ansibleStageOnly" . }}
export ANSIBLE_LOCAL_TMP=/tmp/ansible-tmp
{{- $verbosity := .Values.ansible.verbosity | default 0 | int }}
{{- if gt $verbosity 4 }}{{- $verbosity = 4 }}{{- end }}
{{- if lt $verbosity 0 }}{{- $verbosity = 0 }}{{- end }}
{{- if gt $verbosity 0 }}
export ANSIBLE_VERBOSITY={{ $verbosity }}
{{- end }}
python3 -m pip install --user -q --no-warn-script-location 'ansible-core>=2.15,<2.17'
export PATH="/tmp/.local/bin:$PATH"
{{- end }}
