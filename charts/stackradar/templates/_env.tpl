{{- define "stackradar.validate.routing" }}
{{- if and .Values.ingress.enabled .Values.httpRoute.enabled }}
{{- fail "ingress.enabled and httpRoute.enabled are mutually exclusive; both routes would target the same Services. Pick one." }}
{{- end }}
{{- end -}}

{{/*
  In monolith topology the worker.* block renders nothing: the server pod
  runs the job worker with the server's own knobs. Fail loudly when a user
  has touched keys that only take effect in split, so a monolith -> split
  move never meets half-configured worker knobs — and so nobody believes a
  `worker.resources` they set is in effect.
*/}}
{{- define "stackradar.validate.monolithWorker" }}
{{- if eq (include "stackradar.topology" .) "monolith" }}
{{- $w := .Values.worker }}
{{- $touched := list }}
{{- if ne (int $w.replicaCount) 1 }}{{- $touched = append $touched "replicaCount" }}{{- end }}
{{- if $w.autoscaling.enabled }}{{- $touched = append $touched "autoscaling.enabled" }}{{- end }}
{{- if $w.pdb.enabled }}{{- $touched = append $touched "pdb.enabled" }}{{- end }}
{{- if $w.extraEnv }}{{- $touched = append $touched "extraEnv" }}{{- end }}
{{- if $w.extraEnvFrom }}{{- $touched = append $touched "extraEnvFrom" }}{{- end }}
{{- if $w.tolerations }}{{- $touched = append $touched "tolerations" }}{{- end }}
{{- if $w.nodeSelector }}{{- $touched = append $touched "nodeSelector" }}{{- end }}
{{- if $w.affinity }}{{- $touched = append $touched "affinity" }}{{- end }}
{{- if $w.topologySpreadConstraints }}{{- $touched = append $touched "topologySpreadConstraints" }}{{- end }}
{{- if $w.priorityClassName }}{{- $touched = append $touched "priorityClassName" }}{{- end }}
{{- if $w.annotations }}{{- $touched = append $touched "annotations" }}{{- end }}
{{- if $w.podAnnotations }}{{- $touched = append $touched "podAnnotations" }}{{- end }}
{{- if $w.podLabels }}{{- $touched = append $touched "podLabels" }}{{- end }}
{{- if $touched }}
{{- fail (printf "worker.{%s} set, but topology=monolith renders no worker Deployment (the server pod runs the job worker). Set topology=split to run a separate worker, or move these settings to server.*" (join "," $touched)) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  A pre-install hook runs before anything else in the release exists: no
  chart-managed Secret, no bundled Postgres. So the initializer can only read
  what was provisioned beforehand, and the server image's own config check
  (DATABASE_URL, INTERNAL_SERVICE_KEY, API_KEY_ENCRYPTION_KEY) runs before it
  migrates.
*/}}
{{- define "stackradar.validate.initializer" }}
{{- if .Values.initializer.enabled }}
{{- if .Values.postgresql.enabled }}
{{- fail "initializer.enabled is incompatible with the bundled Postgres (postgresql.enabled=true): the pre-install/pre-upgrade hook Job runs before the release's StatefulSet exists and would wait on a database that is not there yet. Use an external database referenced by database.existingSecret.name, or leave the initializer off and let the pods migrate at start-up." }}
{{- end }}
{{- if not .Values.database.existingSecret.name }}
{{- fail "initializer.enabled requires database.existingSecret.name: the pre-install/pre-upgrade hook Job runs before chart-managed Secrets are created, so provision the connection string separately." }}
{{- end }}
{{- if not .Values.secrets.existingSecret.name }}
{{- fail "initializer.enabled requires secrets.existingSecret.name: the hook Job runs the server image, whose start-up check reads INTERNAL_SERVICE_KEY and API_KEY_ENCRYPTION_KEY before it migrates, and chart-managed Secrets do not exist yet when a pre-install hook runs." }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  The scanner subchart's default `stackradar.apiUrl` names
  `<release>-server.<namespace>.svc:8080`. Two knobs of this chart move the
  real Service away from that — `fullnameOverride` and `server.service.port`
  — and a scanner pointed at a Service that does not exist would log
  connection errors forever rather than fail here. Any non-default value is
  the user's deliberate choice (a mesh, TLS) and is trusted.
*/}}
{{- define "stackradar.scanner.defaultApiUrl" -}}
http://{{ "{{" }} .Release.Name {{ "}}" }}-server.{{ "{{" }} .Release.Namespace {{ "}}" }}.svc:8080
{{- end }}

{{- define "stackradar.validate.scannerApiUrl" }}
{{- if .Values.scanner.enabled }}
{{- $configured := .Values.scanner.stackradar.apiUrl }}
{{- $actual := printf "http://%s.%s.svc:%d" (include "stackradar.server.fullname" .) .Release.Namespace (int .Values.server.service.port) }}
{{- if and (eq $configured (include "stackradar.scanner.defaultApiUrl" .)) (ne (tpl $configured .) $actual) }}
{{- fail (printf "scanner.stackradar.apiUrl is at its default, which names %s, but this release's server Service is %s (fullnameOverride or server.service.port changed it). Set scanner.stackradar.apiUrl=%s" (tpl $configured .) $actual $actual) }}
{{- end }}
{{- end }}
{{- end }}

{{- define "stackradar.validate.all" }}
{{- include "stackradar.validate.routing" . }}
{{- include "stackradar.validate.monolithWorker" . }}
{{- include "stackradar.validate.secrets" . }}
{{- include "stackradar.validate.database" . }}
{{- include "stackradar.validate.bootstrap" . }}
{{- include "stackradar.validate.auth" . }}
{{- include "stackradar.validate.initializer" . }}
{{- include "stackradar.validate.scannerApiUrl" . }}
{{- end -}}

{{/*
  DATABASE_URL for any pod. Bundled Postgres: the role password comes from
  its Secret and the URL is assembled by the kubelet's `$(VAR)` expansion,
  so the chart stores no URL anywhere. `sslmode=prefer`: the bundled server
  has no certificate and sits on the cluster network. External: the URL
  itself from its Secret, plus the CA PEM when the Secret carries one.
*/}}
{{- define "stackradar.databaseEnv" }}
{{- $ctx := .ctx }}
{{- $v := $ctx.Values }}
{{- if $v.postgresql.enabled }}
- name: STACKRADAR_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.postgresql.secretName" $ctx }}
      key: {{ include "stackradar.postgresql.passwordKey" $ctx }}
- name: DATABASE_URL
  value: {{ printf "postgresql://%s:$(STACKRADAR_DB_PASSWORD)@%s:5432/%s?sslmode=prefer" $v.postgresql.auth.username (include "stackradar.postgresql.host" $ctx) $v.postgresql.auth.database | quote }}
{{- else }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.db.secretName" $ctx }}
      key: {{ include "stackradar.db.urlKey" $ctx }}
{{- if and $v.database.existingSecret.name $v.database.existingSecret.caCertKey }}
- name: DATABASE_CA_CERT
  valueFrom:
    secretKeyRef:
      name: {{ $v.database.existingSecret.name }}
      key: {{ $v.database.existingSecret.caCertKey }}
{{- end }}
{{- end }}
{{- end }}

{{/*
  The server image's environment, by role:
    monolith    — API + job worker + in-process syncs (the default install)
    web         — API only (split topology)
    worker      — `dist/src/worker.js` (split)
    sync        — one of the sync CLIs (split CronJobs)
    initializer — migrate and exit (the hook Job)
  Validation runs here because every rendered workload goes through it.
*/}}
{{- define "stackradar.serverEnv" }}
{{- $ctx := .ctx }}
{{- $role := .role }}
{{- $v := $ctx.Values }}
{{- include "stackradar.validate.all" $ctx -}}
{{- include "stackradar.databaseEnv" (dict "ctx" $ctx) }}
- name: STACKRADAR_EDITION
  value: community
- name: LOG_LEVEL
  value: {{ $v.logLevel | quote }}
# syft and helm write caches under $HOME; with a read-only root filesystem that lives on /tmp.
- name: HOME
  value: /tmp
- name: INTERNAL_SERVICE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.secrets.secretName" $ctx }}
      key: {{ include "stackradar.secrets.internalServiceKeyKey" $ctx }}
- name: API_KEY_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.secrets.secretName" $ctx }}
      key: {{ include "stackradar.secrets.apiKeyEncryptionKeyKey" $ctx }}
{{- if eq $role "initializer" }}
- name: MIGRATE_EXIT_AFTER
  value: "true"
{{- else }}
- name: TOPOLOGY
  value: {{ include "stackradar.topology" $ctx }}
{{- with $v.vulnerabilityData.osvEcosystems }}
- name: OSV_ECOSYSTEMS
  value: {{ . | quote }}
{{- end }}
- name: ARTIFACT_HUB_SYNC_ENABLED
  value: {{ $v.vulnerabilityData.artifactHubSync.enabled | toString | quote }}
{{- end }}
{{- if or (eq $role "monolith") (eq $role "web") }}
{{- if not $v.initializer.enabled }}
- name: MIGRATE_ON_START
  value: "true"
{{- end }}
- name: APP_URL
  value: {{ include "stackradar.externalUrl" $ctx | quote }}
- name: NODE_OPTIONS
  value: {{ $v.server.nodeOptions | quote }}
{{- if $v.scanner.enabled }}
- name: BOOTSTRAP_CLUSTER_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.bootstrap.secretName" $ctx }}
      key: {{ include "stackradar.bootstrap.clusterIdKey" $ctx }}
- name: BOOTSTRAP_CLUSTER_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.bootstrap.secretName" $ctx }}
      key: {{ include "stackradar.bootstrap.apiKeyKey" $ctx }}
{{- end }}
{{- end }}
{{- if eq $role "monolith" }}
- name: OSV_SYNC_CRON
  value: {{ $v.sync.osv.schedule | quote }}
- name: OSV_BOOTSTRAP_CRON
  value: {{ $v.sync.osvBootstrap.schedule | quote }}
- name: EPSS_SYNC_CRON
  value: {{ $v.sync.epss.schedule | quote }}
- name: KEV_SYNC_CRON
  value: {{ $v.sync.kev.schedule | quote }}
- name: ARTIFACT_HUB_SYNC_CRON
  value: {{ $v.sync.artifactHub.schedule | quote }}
{{- end }}
{{- if eq $role "worker" }}
- name: GOMEMLIMIT
  value: {{ $v.worker.gomemlimit | quote }}
{{- end }}
{{- if ne $role "initializer" }}
{{- with $v.server.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- if eq $role "worker" }}
{{- with $v.worker.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- end -}}

{{/* The client image's environment. Roles: `client`, `initializer`. */}}
{{- define "stackradar.clientEnv" }}
{{- $ctx := .ctx }}
{{- $role := .role }}
{{- $v := $ctx.Values }}
{{- include "stackradar.validate.all" $ctx -}}
{{- include "stackradar.databaseEnv" (dict "ctx" $ctx) }}
- name: STACKRADAR_EDITION
  value: community
- name: LOG_LEVEL
  value: {{ $v.logLevel | quote }}
- name: HOME
  value: /tmp
{{- if eq $role "initializer" }}
- name: MIGRATE_EXIT_AFTER
  value: "true"
{{- else }}
{{- if not $v.initializer.enabled }}
- name: MIGRATE_ON_START
  value: "true"
{{- end }}
- name: EXPRESS_API_URL
  value: {{ printf "http://%s:%d" (include "stackradar.server.fullname" $ctx) (int $v.server.service.port) | quote }}
- name: INTERNAL_SERVICE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.secrets.secretName" $ctx }}
      key: {{ include "stackradar.secrets.internalServiceKeyKey" $ctx }}
- name: AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.secrets.secretName" $ctx }}
      key: {{ include "stackradar.secrets.authSecretKey" $ctx }}
{{- if eq (include "stackradar.hasExternalUrl" $ctx) "true" }}
- name: AUTH_URL
  value: {{ include "stackradar.externalUrl" $ctx | quote }}
{{- else }}
# No hostname is known (port-forward install): Auth.js trusts the Host header.
- name: AUTH_TRUST_HOST
  value: "true"
{{- end }}
- name: AUTH_LOCAL_ENABLED
  value: {{ $v.auth.local.enabled | toString | quote }}
{{- if $v.auth.local.enabled }}
- name: AUTH_BOOTSTRAP_ADMIN_EMAIL
  value: {{ $v.auth.local.adminEmail | quote }}
- name: AUTH_BOOTSTRAP_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.secrets.secretName" $ctx }}
      key: {{ include "stackradar.secrets.adminPasswordKey" $ctx }}
{{- end }}
{{- range $name := list "oidc" "github" "google" }}
{{- if eq (include "stackradar.auth.providerEnabled" (dict "ctx" $ctx "name" $name)) "true" }}
- name: AUTH_{{ upper $name }}_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.auth.providerSecretName" (dict "ctx" $ctx "name" $name) }}
      key: {{ include "stackradar.auth.providerClientIdKey" (dict "ctx" $ctx "name" $name) }}
- name: AUTH_{{ upper $name }}_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "stackradar.auth.providerSecretName" (dict "ctx" $ctx "name" $name) }}
      key: {{ include "stackradar.auth.providerClientSecretKey" (dict "ctx" $ctx "name" $name) }}
{{- end }}
{{- end }}
{{- if eq (include "stackradar.auth.providerEnabled" (dict "ctx" $ctx "name" "oidc")) "true" }}
- name: AUTH_OIDC_ISSUER
  value: {{ $v.auth.oidc.issuer | quote }}
{{- with $v.auth.oidc.name }}
- name: AUTH_OIDC_NAME
  value: {{ . | quote }}
{{- end }}
{{- with $v.auth.oidc.scope }}
- name: AUTH_OIDC_SCOPE
  value: {{ . | quote }}
{{- end }}
{{- with $v.auth.oidc.adminGroup }}
- name: AUTH_OIDC_ADMIN_GROUP
  value: {{ . | quote }}
{{- end }}
{{- with $v.auth.oidc.groupsClaim }}
- name: AUTH_OIDC_GROUPS_CLAIM
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- with $v.client.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
  Shared pod-spec fragments. `waitForPostgres` holds a pod until the bundled
  database answers, so a fresh install's first start does not spin on
  "connection refused" while the StatefulSet initialises its volume.
*/}}
{{- define "stackradar.waitForPostgresInitContainer" }}
{{- if .Values.postgresql.enabled }}
- name: wait-for-postgres
  image: {{ include "stackradar.postgresql.image" . }}
  imagePullPolicy: {{ .Values.postgresql.image.pullPolicy }}
  securityContext: {{- toYaml .Values.postgresql.securityContext | nindent 4 }}
  command:
    - sh
    - -c
    - |
      until pg_isready -h {{ include "stackradar.postgresql.host" . }} -p 5432 -U {{ .Values.postgresql.auth.username }}; do
        echo "waiting for postgres"
        sleep 2
      done
  resources:
    requests:
      cpu: 10m
      memory: 16Mi
    limits:
      memory: 64Mi
{{- end }}
{{- end -}}
