{{- define "product.name" -}}{{ .Release.Name }}{{- end -}}
{{- define "product.labels" -}}
app.kubernetes.io/name: {{ include "product.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | replace "+" "_" | replace ":" "_" | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
platform/customer: {{ .Values.customer | quote }}
platform/env: {{ .Values.env | quote }}
{{- end -}}
{{- define "product.selector" -}}
app.kubernetes.io/name: {{ include "product.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
