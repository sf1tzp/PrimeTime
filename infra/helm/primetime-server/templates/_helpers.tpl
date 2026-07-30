{{/* Expand the name of the chart. */}}
{{- define "primetime-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "primetime-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "primetime-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Image tag: explicit value, else "v<appVersion>". */}}
{{- define "primetime-server.imageTag" -}}
{{- .Values.image.tag | default (printf "v%s" .Chart.AppVersion) }}
{{- end }}

{{/* Secret name holding the admin credentials. */}}
{{- define "primetime-server.adminSecretName" -}}
{{- if .Values.admin.existingSecret }}
{{- .Values.admin.existingSecret }}
{{- else }}
{{- printf "%s-admin" (include "primetime-server.fullname" .) }}
{{- end }}
{{- end }}

{{/* PVC name. */}}
{{- define "primetime-server.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "primetime-server.fullname" .) }}
{{- end }}
{{- end }}

{{- define "primetime-server.labels" -}}
helm.sh/chart: {{ include "primetime-server.chart" . }}
{{ include "primetime-server.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "primetime-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "primetime-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
