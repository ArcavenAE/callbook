{{- define "dolt.fullname" -}}
{{ .Values.namePrefix }}{{ .Values.project }}
{{- end }}

{{- define "dolt.labels" -}}
app.kubernetes.io/name: dolt
app.kubernetes.io/instance: {{ include "dolt.fullname" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
callbook.arcaven.com/project: {{ .Values.project }}
{{- end }}

{{- define "dolt.selectorLabels" -}}
app.kubernetes.io/name: dolt
app.kubernetes.io/instance: {{ include "dolt.fullname" . }}
{{- end }}

{{- define "dolt.tlsSecretName" -}}
{{ .Values.tls.secretName | default (printf "%s-tls" (include "dolt.fullname" .)) }}
{{- end }}
