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

{{/*
Build the Typesafe Config `override_with_env_vars` env-var name for a federation->sidecar
credential leaf (Story 16.3). VERIFIED mangling (github.com/lightbend/config): strip
CONFIG_FORCE_, then `_`->`.`, `__`->`-`, `___`->`_`. So to TARGET a path containing dashes
we EMIT `__`. Input: dict {name: <sidecar name>, key: <dash-cased credential key e.g.
"bearer-token">}. The fixed path arrow.flight.federation.servers.<name>.credentials.<key> ->
  CONFIG_FORCE_arrow_flight_federation_servers_<name|->__>_credentials_<key|->__>
Example: name="prod-us" key="bearer-token" ->
  CONFIG_FORCE_arrow_flight_federation_servers_prod__us_credentials_bearer__token
GUARD: the mangling is injective ONLY for RFC1123-label sidecar names (lowercase
alphanumeric + '-'). A name containing '_'/'.'/uppercase would mangle to a WRONG
CONFIG_FORCE_* path that silently does NOT override (-> federation validate() CrashLoop).
The sidecar-name validation block in federation-configmap.yaml enforces a strict RFC1123
check, so by the time this helper runs the name is guaranteed dash-only — the
`replace "-" "__"` transform is then reversible/injective.
*/}}
{{- define "softclient4es-federation.configForceEnvName" -}}
{{- $name := .name | replace "-" "__" -}}
{{- $key := .key | replace "-" "__" -}}
{{- printf "CONFIG_FORCE_arrow_flight_federation_servers_%s_credentials_%s" $name $key -}}
{{- end -}}

{{/*
ES Secret data-key for a given logical field, honoring sidecars[].elasticsearch.secretKeys
(Story 16.3). Input: dict {es: $s.elasticsearch, field: "username"} -> the Secret key
(default contract). Falls back to the FACT-C default when no override is given.
*/}}
{{- define "softclient4es-federation.esSecretKey" -}}
{{- $defaults := dict "authMethod" "es-auth-method" "username" "es-username" "password" "es-password" "apiKey" "es-api-key" "bearerToken" "es-bearer-token" -}}
{{- $field := .field -}}
{{- $override := "" -}}
{{- if .es.secretKeys -}}{{- $override = index .es.secretKeys $field | default "" -}}{{- end -}}
{{- if $override -}}{{ $override }}{{- else -}}{{ index $defaults $field }}{{- end -}}
{{- end -}}

{{/*
Arrow-auth Secret data-key for a given logical field, honoring sidecars[].auth.secretKeys
(Story 16.3). Input: dict {auth: $s.auth, field: "bearerToken"} -> the Secret key
(default contract). Falls back to the FACT-C default when no override is given.
*/}}
{{- define "softclient4es-federation.arrowSecretKey" -}}
{{- $defaults := dict "username" "arrow-username" "password" "arrow-password" "bearerToken" "arrow-bearer-token" "apiKey" "arrow-api-key" -}}
{{- $field := .field -}}
{{- $override := "" -}}
{{- if .auth.secretKeys -}}{{- $override = index .auth.secretKeys $field | default "" -}}{{- end -}}
{{- if $override -}}{{ $override }}{{- else -}}{{ index $defaults $field }}{{- end -}}
{{- end -}}
