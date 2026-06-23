{{- define "rdr.regionaldrAnsibleConfigMapData" -}}
{{- $paths := list }}
{{- range $path, $_ := .Files.Glob "ansible/**" }}
{{- if not (hasPrefix "ansible/." $path) }}
{{- $paths = append $paths $path }}
{{- end }}
{{- end }}
{{- range $path := $paths | sortAlpha }}
  {{- $key := $path | trimPrefix "ansible/" | replace "/" "__" }}
  {{- $body := $.Files.Get $path | toString | trimSuffix "\n" }}
  {{ $key }}: |
{{ $body | nindent 4 }}
{{- end }}
{{- end }}
