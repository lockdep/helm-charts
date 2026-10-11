{{/*
  Names are `<release>-<component>`. `fullname` is the release name (or
  `fullnameOverride`), truncated to 45 so the longest suffix (`-osv-bootstrap`,
  14 chars) keeps every resource name under the 63-char label cap. Unlike the
  common `<release>-<chart>` form this gives `stackradar-server` for
  `helm install stackradar`, which is what every documented command names, and
  it is the shape the scanner subchart's default `stackradar.apiUrl`
  (`http://{{ .Release.Name }}-server…`) relies on.
*/}}
{{- define "stackradar.name" }}
{{- default .Chart.Name .Values.nameOverride | trunc 45 | trimSuffix "-" }}
{{- end }}

{{- define "stackradar.fullname" }}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 45 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 45 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "stackradar.chart" }}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "stackradar.commonLabels" -}}
helm.sh/chart: {{ include "stackradar.chart" . }}
app.kubernetes.io/part-of: {{ include "stackradar.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "stackradar.componentFullname" }}
{{- printf "%s-%s" (include "stackradar.fullname" .ctx) .suffix | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
  Selector labels for one component. `app.kubernetes.io/name` carries the
  component so a NetworkPolicy can name "the server pods of this release"
  without a role label.
*/}}
{{- define "stackradar.selectorLabels" -}}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/name: {{ printf "%s-%s" (include "stackradar.name" .ctx) .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "stackradar.componentLabels" -}}
{{ include "stackradar.commonLabels" .ctx }}
{{ include "stackradar.selectorLabels" . }}
app.kubernetes.io/version: {{ .ctx.Chart.AppVersion | quote }}
{{- end -}}

{{/*
  Pod label every chart-managed pod that opens a database connection
  carries; the bundled Postgres' NetworkPolicy admits exactly these.
*/}}
{{- define "stackradar.databaseClientLabel" -}}
stackradar.io/database-client: "true"
{{- end }}

{{- define "stackradar.server.fullname" }}
{{- include "stackradar.componentFullname" (dict "ctx" . "suffix" "server") }}
{{- end }}

{{- define "stackradar.client.fullname" }}
{{- include "stackradar.componentFullname" (dict "ctx" . "suffix" "client") }}
{{- end }}

{{- define "stackradar.worker.fullname" }}
{{- include "stackradar.componentFullname" (dict "ctx" . "suffix" "worker") }}
{{- end }}

{{- define "stackradar.postgresql.fullname" }}
{{- include "stackradar.componentFullname" (dict "ctx" . "suffix" "postgresql") }}
{{- end }}

{{- define "stackradar.serviceAccountName" }}
{{- if .Values.serviceAccount.create }}
{{- default (include "stackradar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "stackradar.topology" }}
{{- $t := .Values.topology | default "monolith" }}
{{- if not (has $t (list "monolith" "split")) }}
{{- fail (printf "topology must be 'monolith' or 'split', got %q" $t) }}
{{- end }}
{{- $t }}
{{- end }}

{{- define "stackradar.workerEnabled" }}
{{- if eq (include "stackradar.topology" .) "split" -}}true{{- end }}
{{- end -}}

{{/*
  The scanner subchart's fullname, computed here because the server reads the
  Secret the subchart renders (`<scanner fullname>`, keys `cluster-id` and
  `api-key`). Mirrors the subchart's own `stackradar-scanner.fullname`: its
  `fullnameOverride`, else the release name when it already contains the
  chart name, else `<release>-<chart name>`. Helm renders an aliased
  dependency with `.Chart.Name` set to the alias, so the chart name here is
  `scanner` (Chart.yaml `alias`), not `stackradar-scanner`: a bare
  `helm install stackradar` gives `stackradar-scanner`.
*/}}
{{- define "stackradar.scanner.chartName" }}
{{- .Values.scanner.nameOverride | default "scanner" }}
{{- end }}

{{- define "stackradar.scanner.fullname" }}
{{- $s := .Values.scanner }}
{{- $chartName := include "stackradar.scanner.chartName" . }}
{{- if $s.fullnameOverride }}
{{- $s.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if contains $chartName .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $chartName | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
  Selector labels of the scanner subchart's watcher pod, for the egress
  allowance in scanner/networkpolicy.yaml and the server's ingress policy.
  `app.kubernetes.io/name` is the subchart's chart name (the alias) unless
  its `nameOverride` says otherwise.
*/}}
{{- define "stackradar.scanner.podSelectorLabels" -}}
app.kubernetes.io/name: {{ include "stackradar.scanner.chartName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: watcher
{{- end }}

{{/*
  The URL the UI is reached at: `externalUrl`, else the routing hostname,
  else the port-forward address NOTES.txt prints. `https` for a hostname
  because that is what an Ingress with TLS or a Gateway serves; an http-only
  Ingress sets `externalUrl` explicitly.
*/}}
{{- define "stackradar.externalUrl" }}
{{- if .Values.externalUrl }}
{{- trimSuffix "/" .Values.externalUrl }}
{{- else if .Values.ingress.enabled }}
{{- printf "%s://%s" (ternary "https" "http" (gt (len .Values.ingress.tls) 0)) .Values.ingress.hostname }}
{{- else if .Values.httpRoute.enabled }}
{{- printf "https://%s" (first .Values.httpRoute.hostnames) }}
{{- else }}
{{- "http://localhost:3000" }}
{{- end }}
{{- end }}

{{/* Whether a browser-facing hostname is configured (so AUTH_URL can be pinned). */}}
{{- define "stackradar.hasExternalUrl" }}
{{- if or .Values.externalUrl .Values.ingress.enabled .Values.httpRoute.enabled -}}true{{- end }}
{{- end -}}

{{/*
  The API origin a scanner in another cluster can reach, or "" when none is
  known. `publicApiUrl` wins; otherwise the route's hostname when it exposes
  `/v1`. Deliberately empty for a port-forward install: the UI then shows a
  placeholder in the install command rather than a host that is not yours.
*/}}
{{- define "stackradar.publicApiUrl" }}
{{- if .Values.publicApiUrl }}
{{- trimSuffix "/" .Values.publicApiUrl }}
{{- else if or (and .Values.ingress.enabled .Values.ingress.exposeApi) (and .Values.httpRoute.enabled .Values.httpRoute.exposeApi) }}
{{- include "stackradar.externalUrl" . }}
{{- end }}
{{- end -}}
