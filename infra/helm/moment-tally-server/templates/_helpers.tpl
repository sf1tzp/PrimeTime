{{/* Expand the name of the chart. */}}
{{- define "moment-tally-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "moment-tally-server.fullname" -}}
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

{{- define "moment-tally-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Image tag: explicit value, else "v<appVersion>". */}}
{{- define "moment-tally-server.imageTag" -}}
{{- .Values.image.tag | default (printf "v%s" .Chart.AppVersion) }}
{{- end }}

{{/* Secret name holding the admin credentials. */}}
{{- define "moment-tally-server.adminSecretName" -}}
{{- if .Values.admin.existingSecret }}
{{- .Values.admin.existingSecret }}
{{- else }}
{{- printf "%s-admin" (include "moment-tally-server.fullname" .) }}
{{- end }}
{{- end }}

{{/* PVC name. */}}
{{- define "moment-tally-server.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "moment-tally-server.fullname" .) }}
{{- end }}
{{- end }}

{{- define "moment-tally-server.labels" -}}
helm.sh/chart: {{ include "moment-tally-server.chart" . }}
{{ include "moment-tally-server.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "moment-tally-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "moment-tally-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
