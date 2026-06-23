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

{{/*
Per-ES-version sidecar image selection (Story 16.2).
Input: a dict {ctx: $, sidecar: $s}. Resolves $s.image.repository/.tag overrides,
else maps elasticsearchVersion (6|7|8|9) to the published image. The tag defaults to
.Chart.AppVersion, overridden by $s.image.tag.
*/}}
{{- define "softclient4es-federation.sidecarImage" -}}
{{- $s := .sidecar -}}
{{- $ctx := .ctx -}}
{{- $tag := $ctx.Chart.AppVersion -}}
{{- if $s.image }}{{- if $s.image.tag }}{{- $tag = $s.image.tag }}{{- end }}{{- end -}}
{{- if and $s.image $s.image.repository -}}
{{- printf "%s:%s" $s.image.repository $tag -}}
{{- else -}}
{{- $v := toString (required (printf "sidecar %q: elasticsearchVersion is required" $s.name) $s.elasticsearchVersion) -}}
{{- $repo := "" -}}
{{- if eq $v "6" -}}{{- $repo = "docker.io/softnetwork/softclient4es6-arrow-flight-sql" -}}
{{- else if eq $v "7" -}}{{- $repo = "docker.io/softnetwork/softclient4es7-arrow-flight-sql" -}}
{{- else if eq $v "8" -}}{{- $repo = "docker.io/softnetwork/softclient4es8-arrow-flight-sql" -}}
{{- else if eq $v "9" -}}{{- $repo = "docker.io/softnetwork/softclient4es9-arrow-flight-sql" -}}
{{- else -}}{{- fail (printf "sidecar %q: unsupported elasticsearchVersion %q (allowed: 6,7,8,9)" $s.name $v) -}}
{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{/* Per-sidecar fullname: <release-fullname>-<sidecar name>, RFC1123, <=63 chars. */}}
{{- define "softclient4es-federation.sidecarFullname" -}}
{{- $base := include "softclient4es-federation.fullname" .ctx -}}
{{- printf "%s-%s" $base .sidecar.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Sidecar selector labels — stable across upgrades; identify the specific sidecar. */}}
{{- define "softclient4es-federation.sidecarSelectorLabels" -}}
app.kubernetes.io/name: {{ include "softclient4es-federation.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: sidecar
softclient4es.app/sidecar: {{ .sidecar.name }}
{{- end -}}

{{/* Sidecar common labels. */}}
{{- define "softclient4es-federation.sidecarLabels" -}}
helm.sh/chart: {{ include "softclient4es-federation.chart" .ctx }}
{{ include "softclient4es-federation.sidecarSelectorLabels" . }}
{{- if .ctx.Chart.AppVersion }}
app.kubernetes.io/version: {{ .ctx.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
app.kubernetes.io/part-of: softclient4es
{{- end -}}

{{/* ES scheme: explicit es.scheme wins; else parsed from url (https://...); else http. */}}
{{- define "softclient4es-federation.esScheme" -}}
{{- $es := .es -}}
{{- if $es.scheme -}}{{ $es.scheme }}
{{- else if and $es.url (hasPrefix "https://" $es.url) -}}https
{{- else -}}http{{- end -}}
{{- end -}}

{{/* ES host: explicit es.host wins; else the host portion of url; else localhost. */}}
{{- define "softclient4es-federation.esHost" -}}
{{- $es := .es -}}
{{- if $es.host -}}{{ $es.host }}
{{- else if $es.url -}}
{{- $hp := $es.url | trimPrefix "https://" | trimPrefix "http://" | trimSuffix "/" -}}
{{- (splitList ":" $hp) | first -}}
{{- else -}}localhost{{- end -}}
{{- end -}}

{{/* ES port: explicit es.port wins; else the port portion of url; else 9200. */}}
{{- define "softclient4es-federation.esPort" -}}
{{- $es := .es -}}
{{- if $es.port -}}{{ $es.port }}
{{- else if $es.url -}}
{{- $hp := $es.url | trimPrefix "https://" | trimPrefix "http://" | trimSuffix "/" -}}
{{- $parts := splitList ":" $hp -}}
{{- if gt (len $parts) 1 -}}{{ last $parts }}{{- else -}}9200{{- end -}}
{{- else -}}9200{{- end -}}
{{- end -}}
