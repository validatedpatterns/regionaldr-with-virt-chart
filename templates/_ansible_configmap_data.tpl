{{- define "rdr.regionaldrAnsibleConfigMapData" -}}
{{- range $path, $content := .Files.Glob "ansible/**" }}
  {{- $key := $path | trimPrefix "ansible/" | replace "/" "__" }}
  {{ $key }}: |
{{ $content | toString | nindent 4 }}
{{- end }}
{{- end }}
