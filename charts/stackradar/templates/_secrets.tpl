{{/*
  Secrets, Dependency-Track style: an inline value renders a chart-managed
  Secret, an `existingSecret` renders nothing, both at once fails, neither
  fails with the command that generates one. `lookup` appears nowhere in
  this chart and nothing is ever generated: a value that changed on every
  render would rotate the scanner key on every GitOps sync.

  The inline defaults in values.yaml are PUBLIC FIXTURES so a bare install
  works. An inline value equal to its fixture counts as "not set" when an
  `existingSecret` is also given (the user did not touch it), and NOTES.txt
  warns for every fixture still in effect.
*/}}

{{- define "stackradar.fixture.dbPassword" -}}stackradar-fixture-db-password{{- end }}
{{- define "stackradar.fixture.internalServiceKey" -}}stackradar-fixture-internal-service-key{{- end }}
{{- define "stackradar.fixture.apiKeyEncryptionKey" -}}0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef{{- end }}
{{- define "stackradar.fixture.authSecret" -}}stackradar-fixture-auth-secret-change-me{{- end }}
{{- define "stackradar.fixture.scannerApiKey" -}}stackradar-fixture-bootstrap-scanner-key{{- end }}
{{- define "stackradar.fixture.clusterId" -}}8f6b0b7a-0c1e-4f6e-9a4b-2f3d1c0e5a71{{- end }}

{{/* ---- application secrets: <fullname>-secrets ---------------------------- */}}

{{- define "stackradar.secrets.secretName" }}
{{- if .Values.secrets.existingSecret.name }}
{{- .Values.secrets.existingSecret.name }}
{{- else }}
{{- printf "%s-secrets" (include "stackradar.fullname" .) }}
{{- end }}
{{- end }}

{{- define "stackradar.secrets.chartManaged" }}
{{- if not .Values.secrets.existingSecret.name -}}true{{- end }}
{{- end }}

{{- define "stackradar.secrets.internalServiceKeyKey" }}
{{- if .Values.secrets.existingSecret.name }}{{ .Values.secrets.existingSecret.internalServiceKeyKey | default "internal-service-key" }}{{ else }}internal-service-key{{ end }}
{{- end }}
{{- define "stackradar.secrets.apiKeyEncryptionKeyKey" }}
{{- if .Values.secrets.existingSecret.name }}{{ .Values.secrets.existingSecret.apiKeyEncryptionKeyKey | default "api-key-encryption-key" }}{{ else }}api-key-encryption-key{{ end }}
{{- end }}
{{- define "stackradar.secrets.authSecretKey" }}
{{- if .Values.secrets.existingSecret.name }}{{ .Values.secrets.existingSecret.authSecretKey | default "auth-secret" }}{{ else }}auth-secret{{ end }}
{{- end }}
{{- define "stackradar.secrets.adminPasswordKey" }}
{{- if .Values.secrets.existingSecret.name }}{{ .Values.secrets.existingSecret.adminPasswordKey | default "admin-password" }}{{ else }}admin-password{{ end }}
{{- end }}

{{- define "stackradar.validate.secrets" }}
{{- $s := .Values.secrets }}
{{- if $s.existingSecret.name }}
{{- $touched := list }}
{{- if ne $s.internalServiceKey (include "stackradar.fixture.internalServiceKey" .) }}{{- $touched = append $touched "internalServiceKey" }}{{- end }}
{{- if ne $s.apiKeyEncryptionKey (include "stackradar.fixture.apiKeyEncryptionKey" .) }}{{- $touched = append $touched "apiKeyEncryptionKey" }}{{- end }}
{{- if ne $s.authSecret (include "stackradar.fixture.authSecret" .) }}{{- $touched = append $touched "authSecret" }}{{- end }}
{{- if ne .Values.auth.local.adminPassword "admin" }}{{- $touched = append $touched "auth.local.adminPassword" }}{{- end }}
{{- if $touched }}
{{- fail (printf "secrets.existingSecret.name is set; leave secrets.{%s} at their defaults to avoid ambiguity about which values are in effect" (join "," $touched)) }}
{{- end }}
{{- else }}
{{- $missing := list }}
{{- if not $s.internalServiceKey }}{{- $missing = append $missing "secrets.internalServiceKey (openssl rand -hex 32)" }}{{- end }}
{{- if not $s.apiKeyEncryptionKey }}{{- $missing = append $missing "secrets.apiKeyEncryptionKey (openssl rand -hex 32)" }}{{- end }}
{{- if not $s.authSecret }}{{- $missing = append $missing "secrets.authSecret (openssl rand -base64 32)" }}{{- end }}
{{- if and .Values.auth.local.enabled (not .Values.auth.local.adminPassword) }}{{- $missing = append $missing "auth.local.adminPassword" }}{{- end }}
{{- if $missing }}
{{- fail (printf "the chart never generates secrets; set %s, or provision them in a Secret and reference it via secrets.existingSecret.name" (join ", " $missing)) }}
{{- end }}
{{- if and $s.apiKeyEncryptionKey (not (regexMatch "^[0-9a-fA-F]{64}$" $s.apiKeyEncryptionKey)) }}
{{- fail "secrets.apiKeyEncryptionKey must be 64 hex characters (openssl rand -hex 32)" }}
{{- end }}
{{- end }}
{{- end }}

{{/* ---- database connection ------------------------------------------------ */}}

{{/*
  Where DATABASE_URL comes from. Bundled Postgres: assembled in the pod from
  the role password (`$(…)` expansion in `env[].value`), so the password
  lives in one Secret — chart-managed or yours — and the URL is never stored.
  External: a Secret holding the whole URL, chart-managed from `database.url`
  or `database.existingSecret`.
*/}}
{{- define "stackradar.db.secretName" }}
{{- if .Values.database.existingSecret.name }}
{{- .Values.database.existingSecret.name }}
{{- else }}
{{- printf "%s-db" (include "stackradar.fullname" .) }}
{{- end }}
{{- end }}

{{- define "stackradar.db.urlKey" }}
{{- if .Values.database.existingSecret.name }}{{ .Values.database.existingSecret.urlKey | default "url" }}{{ else }}url{{ end }}
{{- end }}

{{- define "stackradar.db.chartManaged" }}
{{- if and (not .Values.postgresql.enabled) (not .Values.database.existingSecret.name) -}}true{{- end }}
{{- end }}

{{- define "stackradar.postgresql.secretName" }}
{{- if .Values.postgresql.auth.existingSecret.name }}
{{- .Values.postgresql.auth.existingSecret.name }}
{{- else }}
{{- include "stackradar.postgresql.fullname" . }}
{{- end }}
{{- end }}

{{- define "stackradar.postgresql.passwordKey" }}
{{- if .Values.postgresql.auth.existingSecret.name }}{{ .Values.postgresql.auth.existingSecret.passwordKey | default "password" }}{{ else }}password{{ end }}
{{- end }}

{{- define "stackradar.postgresql.chartManaged" }}
{{- if and .Values.postgresql.enabled (not .Values.postgresql.auth.existingSecret.name) -}}true{{- end }}
{{- end }}

{{- define "stackradar.postgresql.host" }}
{{- printf "%s.%s.svc" (include "stackradar.postgresql.fullname" .) .Release.Namespace }}
{{- end }}

{{- define "stackradar.validate.database" }}
{{- $d := .Values.database }}
{{- $p := .Values.postgresql }}
{{- if $p.enabled }}
{{- if or $d.url $d.existingSecret.name }}
{{- fail "postgresql.enabled is true (the bundled Postgres) and database.url / database.existingSecret.name point at an external one; both cannot be in effect. Set postgresql.enabled=false to use your own database, or clear database.*" }}
{{- end }}
{{- if $p.auth.existingSecret.name }}
{{- if ne $p.auth.password (include "stackradar.fixture.dbPassword" .) }}
{{- fail "postgresql.auth.existingSecret.name is set; leave postgresql.auth.password at its default to avoid ambiguity about which password is in effect" }}
{{- end }}
{{- else if not $p.auth.password }}
{{- fail "postgresql.auth.password must be set (openssl rand -hex 24; keep it URL-safe), or postgresql.auth.existingSecret.name must reference an existing Secret" }}
{{- end }}
{{- else }}
{{- if $d.existingSecret.name }}
{{- if $d.url }}
{{- fail "database.existingSecret.name is set; remove database.url to avoid ambiguity about which connection string is in effect" }}
{{- end }}
{{- else if not $d.url }}
{{- fail "postgresql.enabled is false, so the chart needs an external database: set database.url (postgresql://user:password@host:5432/db?sslmode=require), or provision it in a Secret and reference it via database.existingSecret.name" }}
{{- else if not (regexMatch "[?&]sslmode=(require|verify-ca|verify-full|prefer)([&]|$)" $d.url) }}
{{- fail "database.url must carry an explicit sslmode (require, verify-ca or verify-full for a managed database; prefer for one on a private network): the server refuses a production connection string that says nothing about TLS" }}
{{- end }}
{{- end }}
{{- end }}

{{/* ---- scanner bootstrap credential ------------------------------------- */}}

{{/*
  The one Secret both sides read: the scanner subchart renders it from
  `scanner.stackradar.clusterId` / `.apiKey` under its own fullname (keys
  `cluster-id` / `api-key`), or reads `scanner.stackradar.existingSecret`;
  the server reads the same object for BOOTSTRAP_CLUSTER_ID /
  BOOTSTRAP_CLUSTER_API_KEY. Only meaningful while `scanner.enabled`.
*/}}
{{- define "stackradar.bootstrap.secretName" }}
{{- .Values.scanner.stackradar.existingSecret | default (include "stackradar.scanner.fullname" .) }}
{{- end }}
{{- define "stackradar.bootstrap.clusterIdKey" }}
{{- .Values.scanner.stackradar.existingSecretKeyClusterId | default "cluster-id" }}
{{- end }}
{{- define "stackradar.bootstrap.apiKeyKey" }}
{{- .Values.scanner.stackradar.existingSecretKeyApiKey | default "api-key" }}
{{- end }}

{{- define "stackradar.validate.bootstrap" }}
{{- if .Values.scanner.enabled }}
{{- $b := .Values.scanner.stackradar }}
{{- if $b.existingSecret }}
{{- $touched := list }}
{{- if ne $b.clusterId (include "stackradar.fixture.clusterId" .) }}{{- $touched = append $touched "clusterId" }}{{- end }}
{{- if ne $b.apiKey (include "stackradar.fixture.scannerApiKey" .) }}{{- $touched = append $touched "apiKey" }}{{- end }}
{{- if $touched }}
{{- fail (printf "scanner.stackradar.existingSecret is set; leave scanner.stackradar.{%s} at their defaults to avoid ambiguity about which credential is in effect" (join "," $touched)) }}
{{- end }}
{{- else }}
{{- if or (not $b.clusterId) (not $b.apiKey) }}
{{- fail "the scanner needs a bootstrap credential and the chart never generates one: set scanner.stackradar.clusterId (uuidgen | tr A-Z a-z) and scanner.stackradar.apiKey (openssl rand -hex 32), or provision both in a Secret with keys cluster-id and api-key and reference it via scanner.stackradar.existingSecret" }}
{{- end }}
{{- if not (regexMatch "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" $b.clusterId) }}
{{- fail (printf "scanner.stackradar.clusterId must be a UUID (got %q); the server refuses anything else at boot" $b.clusterId) }}
{{- end }}
{{- if lt (len $b.apiKey) 16 }}
{{- fail "scanner.stackradar.apiKey must be at least 16 characters; the server treats a shorter key as a typo (openssl rand -hex 32)" }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/* ---- sign-in providers ------------------------------------------------- */}}

{{- define "stackradar.auth.secretName" }}
{{- printf "%s-auth" (include "stackradar.fullname" .) }}
{{- end }}

{{/* A provider is on when it has an existingSecret or both inline values. Takes (dict "ctx" . "name" "oidc"). */}}
{{- define "stackradar.auth.providerEnabled" }}
{{- $p := index .ctx.Values.auth .name }}
{{- if or $p.existingSecret.name (and $p.clientId $p.clientSecret) -}}true{{- end }}
{{- end }}

{{- define "stackradar.auth.providerSecretName" }}
{{- $p := index .ctx.Values.auth .name }}
{{- $p.existingSecret.name | default (include "stackradar.auth.secretName" .ctx) }}
{{- end }}
{{- define "stackradar.auth.providerClientIdKey" }}
{{- $p := index .ctx.Values.auth .name }}
{{- if $p.existingSecret.name }}{{ $p.existingSecret.clientIdKey | default "client-id" }}{{ else }}{{ printf "%s-client-id" .name }}{{ end }}
{{- end }}
{{- define "stackradar.auth.providerClientSecretKey" }}
{{- $p := index .ctx.Values.auth .name }}
{{- if $p.existingSecret.name }}{{ $p.existingSecret.clientSecretKey | default "client-secret" }}{{ else }}{{ printf "%s-client-secret" .name }}{{ end }}
{{- end }}

{{/* Whether any provider renders into the chart-managed auth Secret. */}}
{{- define "stackradar.auth.chartManaged" }}
{{- range $name := list "oidc" "github" "google" }}
{{- $p := index $.Values.auth $name }}
{{- if and (not $p.existingSecret.name) $p.clientId $p.clientSecret -}}true{{- end }}
{{- end }}
{{- end }}

{{- define "stackradar.validate.auth" }}
{{- range $name := list "oidc" "github" "google" }}
{{- $p := index $.Values.auth $name }}
{{- if $p.existingSecret.name }}
{{- if or $p.clientId $p.clientSecret }}
{{- fail (printf "auth.%s.existingSecret.name is set; remove auth.%s.clientId and auth.%s.clientSecret to avoid ambiguity about which credentials are in effect" $name $name $name) }}
{{- end }}
{{- else if and (or $p.clientId $p.clientSecret) (not (and $p.clientId $p.clientSecret)) }}
{{- fail (printf "auth.%s is half-configured: set both auth.%s.clientId and auth.%s.clientSecret, or neither (the client refuses to serve a half-configured sign-in)" $name $name $name) }}
{{- end }}
{{- end }}
{{- $oidc := .Values.auth.oidc }}
{{- $oidcCreds := eq (include "stackradar.auth.providerEnabled" (dict "ctx" . "name" "oidc")) "true" }}
{{- if and $oidcCreds (not $oidc.issuer) }}
{{- fail "auth.oidc has credentials but no auth.oidc.issuer; set the provider's issuer URL (the one that serves /.well-known/openid-configuration)" }}
{{- end }}
{{- if and $oidc.issuer (not $oidcCreds) }}
{{- fail "auth.oidc.issuer is set without credentials; set auth.oidc.clientId and auth.oidc.clientSecret, or auth.oidc.existingSecret.name" }}
{{- end }}
{{- $methods := 0 }}
{{- if .Values.auth.local.enabled }}{{- $methods = add $methods 1 }}{{- end }}
{{- range $name := list "oidc" "github" "google" }}
{{- if eq (include "stackradar.auth.providerEnabled" (dict "ctx" $ "name" $name)) "true" }}{{- $methods = add $methods 1 }}{{- end }}
{{- end }}
{{- if eq (int $methods) 0 }}
{{- fail "no sign-in method is configured: auth.local.enabled is false and no auth.oidc / auth.github / auth.google credentials are set; the client would never become ready" }}
{{- end }}
{{- end }}

{{/* ---- fixtures still in effect (for NOTES.txt) ------------------------- */}}

{{- define "stackradar.fixturesInEffect" }}
{{- $list := list }}
{{- if eq (include "stackradar.secrets.chartManaged" .) "true" }}
{{- if eq .Values.secrets.internalServiceKey (include "stackradar.fixture.internalServiceKey" .) }}{{- $list = append $list "secrets.internalServiceKey" }}{{- end }}
{{- if eq .Values.secrets.apiKeyEncryptionKey (include "stackradar.fixture.apiKeyEncryptionKey" .) }}{{- $list = append $list "secrets.apiKeyEncryptionKey" }}{{- end }}
{{- if eq .Values.secrets.authSecret (include "stackradar.fixture.authSecret" .) }}{{- $list = append $list "secrets.authSecret" }}{{- end }}
{{- end }}
{{- if and (eq (include "stackradar.postgresql.chartManaged" .) "true") (eq .Values.postgresql.auth.password (include "stackradar.fixture.dbPassword" .)) }}{{- $list = append $list "postgresql.auth.password" }}{{- end }}
{{- if and .Values.scanner.enabled (not .Values.scanner.stackradar.existingSecret) (eq .Values.scanner.stackradar.apiKey (include "stackradar.fixture.scannerApiKey" .)) }}{{- $list = append $list "scanner.stackradar.apiKey" }}{{- end }}
{{- join "," $list }}
{{- end -}}
