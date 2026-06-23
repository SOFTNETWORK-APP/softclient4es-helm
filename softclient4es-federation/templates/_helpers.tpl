{{/* Expand the name of the chart. */}}
{{- define "softclient4es-federation.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name (release-scoped, RFC1123, <=63 chars). */}}
{{- define "softclient4es-federation.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "softclient4es-federation.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "softclient4es-federation.labels" -}}
helm.sh/chart: {{ include "softclient4es-federation.chart" . }}
{{ include "softclient4es-federation.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: federation
app.kubernetes.io/part-of: softclient4es
{{- end -}}

{{/* Selector labels — stable across upgrades; do NOT add version here. */}}
{{- define "softclient4es-federation.selectorLabels" -}}
app.kubernetes.io/name: {{ include "softclient4es-federation.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "softclient4es-federation.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "softclient4es-federation.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
