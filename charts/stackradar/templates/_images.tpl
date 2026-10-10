{{/*
  `<registry>/<repository>:<tag>` or `<registry>/<repository>@sha256:…`. The
  tag defaults to the chart's appVersion. A tag whose major differs from the
  appVersion's major is refused: a chart written for 0.x must never silently
  run a 1.x server against the same database. Non-semver tags (`snapshot`,
  `latest`) and digests are not checked — they are a deliberate choice.
*/}}
{{- define "stackradar.image" }}
{{- $registry := .image.registry | default .fallbackRegistry }}
{{- $repo := .image.repository }}
{{- $tag := .image.tag | default .fallbackTag }}
{{- if and (ne (substr 0 7 $tag) "sha256:") (regexMatch "^v?[0-9]+\\." $tag) }}
{{- $major := regexFind "^v?[0-9]+" $tag | trimPrefix "v" }}
{{- $supported := regexFind "^v?[0-9]+" .appVersion | trimPrefix "v" }}
{{- if ne $major $supported }}
{{- fail (printf "image tag %q is not supported by this chart version (chart %s installs StackRadar %s; a %s.x image needs the matching chart major)" $tag .chartVersion .appVersion $major) }}
{{- end }}
{{- end }}
{{- if eq (substr 0 7 $tag) "sha256:" }}
{{- printf "%s/%s@%s" $registry $repo $tag }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repo $tag }}
{{- end }}
{{- end }}

{{- define "stackradar.server.image" }}
{{- include "stackradar.image" (dict "image" .Values.server.image "fallbackRegistry" .Values.image.registry "fallbackTag" .Chart.AppVersion "appVersion" .Chart.AppVersion "chartVersion" .Chart.Version) }}
{{- end }}

{{- define "stackradar.client.image" }}
{{- include "stackradar.image" (dict "image" .Values.client.image "fallbackRegistry" .Values.image.registry "fallbackTag" .Chart.AppVersion "appVersion" .Chart.AppVersion "chartVersion" .Chart.Version) }}
{{- end }}

{{/* The bundled Postgres: tag and, when set, digest — `postgres:18-alpine@sha256:…`. */}}
{{- define "stackradar.postgresql.image" }}
{{- $i := .Values.postgresql.image }}
{{- $registry := $i.registry | default .Values.image.registry }}
{{- if $i.digest }}
{{- printf "%s/%s:%s@%s" $registry $i.repository $i.tag $i.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $i.repository $i.tag }}
{{- end }}
{{- end -}}
