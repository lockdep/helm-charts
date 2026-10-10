# stackradar

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

StackRadar Community Edition: what is running in your Kubernetes cluster,
which of it is vulnerable, and what to move to. Installs the server, the
UI, a bundled Postgres and the scanner, already scanning the cluster it
lands in.

**Homepage:** <https://stackradar.io>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| StackRadar | <support@stackradar.io> | <https://stackradar.io> |

## Source Code

* <https://github.com/lockdep/helm-charts/tree/main/charts/stackradar>
* <https://github.com/lockdep/stackradar>

## Requirements

Kubernetes: `>=1.25.0-0`

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/lockdep/charts | scanner(stackradar-scanner) | 0.5.0 |

> [!IMPORTANT]
> **Read the upgrade notes before you upgrade `appVersion`.**
> StackRadar releases can carry schema migrations and breaking changes
> that the chart does not shield you from.
>
> 1. The [self-hosting guide](https://github.com/lockdep/stackradar/blob/main/docs/self-hosting/helm.md)
>    covers the procedure.
> 2. The [release notes](https://github.com/lockdep/stackradar/releases)
>    of every version you skip past, not just the target one.
> 3. [UPGRADING.md](https://github.com/lockdep/helm-charts/blob/main/charts/stackradar/UPGRADING.md)
>    covers the chart-level changes.

## Quickstart

One command on any Kubernetes 1.25+ cluster. No values file, no Postgres to
bring, no second command for the scanner:

```sh
helm install stackradar oci://ghcr.io/lockdep/helm-charts/stackradar \
  --namespace stackradar --create-namespace

kubectl -n stackradar port-forward svc/stackradar-client 3000:3000
```

Open http://localhost:3000 and log in as `admin@stackradar.local` /
`admin`. You will be asked to change the password; do it before exposing
the install beyond localhost. The scanner installed alongside is already
sweeping the cluster; its images appear with findings once the OSV mirror
has bootstrapped (minutes, depending on your connection — the UI says so
until then).

On a laptop cluster (kind, minikube, Docker Desktop) add the trimmed
sizing and the two-minute Alpine-only mirror:

```sh
helm install stackradar oci://ghcr.io/lockdep/helm-charts/stackradar \
  --namespace stackradar --create-namespace \
  -f https://raw.githubusercontent.com/lockdep/helm-charts/main/charts/stackradar/values-quickstart.yaml
```

> [!WARNING]
> **Every secret the bare install uses is a public fixture** — the
> database password, the service key, the encryption key, the session
> secret and the scanner's bootstrap key are the same on every install
> that leaves them at their defaults, and `helm install` prints a WARNING
> naming each one still in effect. With the fixture scanner key, any pod
> in the cluster that can reach the server Service can upload SBOMs as
> the local cluster. Before relying on the install, set your own values
> or reference existing Secrets (see [Secrets](#secrets)). The chart
> never generates a secret for you: a generated value would change on
> every GitOps render and rotate the scanner key each sync.

## What gets installed

| Component | Default | Notes |
|---|---|---|
| `server` Deployment | 1 replica, `monolith` topology | The API, the job worker and the OSV / EPSS / KEV sync schedule in one process. |
| `client` Deployment | 1 replica | The web UI (Next.js), which also keeps its Auth.js tables in the `auth` schema of the same database. |
| `postgresql` StatefulSet | bundled, 10Gi retained volume | See [Bundled Postgres](#bundled-postgres). |
| `stackradar-scanner` | subchart, on | Scans the cluster it lands in and reports to the server Service in-cluster. |
| `worker` Deployment, sync CronJobs | only with `topology: split` | The cloud's shape, for installs that scale the pieces separately. |
| Ingress or HTTPRoute, NetworkPolicies, ServiceMonitor, PrometheusRule, PDBs, HPAs | off | Enable per block. |

Names are `<release>-<component>`: `stackradar-server`, `stackradar-client`,
`stackradar-postgresql`, and the scanner's `stackradar-scanner-watcher` for
`helm install stackradar`.

## Secrets

Three application secrets, the database password and the scanner's
bootstrap credential. Each follows the same rule:

- **Inline value** (`secrets.internalServiceKey`, `postgresql.auth.password`,
  `scanner.stackradar.apiKey`, …) ⇒ the chart renders the Secret. The
  defaults are public fixtures; replace them with `openssl rand -hex 32`
  (`uuidgen | tr A-Z a-z` for the cluster id).
- **`existingSecret`** (`secrets.existingSecret.name`,
  `postgresql.auth.existingSecret.name`, `database.existingSecret.name`,
  `scanner.stackradar.existingSecret`, `auth.<provider>.existingSecret.name`)
  ⇒ the chart renders nothing and reads yours; the inline values must be
  left at their defaults, or the render fails rather than guess which is in
  effect. Compatible with external-secrets, sealed-secrets and SOPS.
- **Neither** (an inline value blanked) ⇒ the render fails with the command
  that generates one.

A production install provisions four Secrets beforehand and references
them:

```yaml
secrets:
  existingSecret:
    name: stackradar-secrets        # internal-service-key, api-key-encryption-key, auth-secret, admin-password
postgresql:
  enabled: false
database:
  existingSecret:
    name: stackradar-db             # url: postgresql://…?sslmode=require
scanner:
  stackradar:
    existingSecret: stackradar-bootstrap   # cluster-id, api-key
auth:
  oidc:
    issuer: https://idp.example.com/realms/stackradar
    existingSecret:
      name: stackradar-oidc         # client-id, client-secret
```

The scanner's bootstrap credential is read by both sides: the scanner
authenticates with it and the server creates the cluster `local` and that
key at start-up from the same Secret. That is what makes the install one
command. The proper fix — the scanner authenticating with a projected
ServiceAccount token and no shared secret at all — is the first
post-launch item.

## Bundled Postgres

`postgresql.enabled: true` (the default) renders a single-replica
StatefulSet on `postgres:18-alpine`, pinned by digest, with a retained data
volume and a NetworkPolicy that admits only this release's pods — rendered
whatever `networkPolicy.enabled` says, because a database whose password
may still be the public fixture must not be reachable from every pod in the
cluster. `helm uninstall` never deletes the volume.

What it is not: highly available, backed up, or upgraded across Postgres
majors for you. There is no backup CronJob in this chart version; back it
up yourself:

```sh
kubectl -n stackradar exec stackradar-postgresql-0 -- \
  pg_dump -U stackradar -Fc stackradar > stackradar.dump
```

### Moving to your own Postgres

1. Scale the apps down so nothing writes: `kubectl -n stackradar scale deploy stackradar-server stackradar-client --replicas=0`.
2. Dump the bundle (above) and restore it into the new database:
   `pg_restore -d "postgresql://…/stackradar?sslmode=require" --no-owner stackradar.dump`.
   The restore needs the `auth` and `drizzle` schemas and both apps' migration
   journals, which `-Fc` carries.
3. Put the new connection string in a Secret (`url` key) and flip the values:
   `postgresql.enabled: false`, `database.existingSecret.name: <secret>`.
4. `helm upgrade`. The pods come up against the new database; the chain is
   already applied, so the start-up migration is a no-op.
5. Once satisfied, delete the retained claim `data-stackradar-postgresql-0`.

## Topology

`topology: monolith` (default) is `server` + `client` + the scanner. The
server process runs the job worker and an in-process cron for the
vulnerability feeds on the same schedules as the cloud's CronJobs, in UTC
(`sync.*.schedule`). Replicas are safe: the queue claims with
`SKIP LOCKED` and every sync takes a Postgres advisory lock.

`topology: split` renders the `worker` Deployment and one CronJob per feed
(`osv-sync`, `osv-bootstrap`, `epss-sync`, `kev-sync`, and
`artifacthub-sync` when `vulnerabilityData.artifactHubSync.enabled`), and
the server is HTTP-only. Setting `worker.*` knobs under `monolith` fails
the render rather than being ignored.

## Vulnerability data

The server mirrors OSV, EPSS and KEV itself; nothing phones home.
`vulnerabilityData.osvEcosystems` scopes the mirror: empty is the community
default list (the base images and package managers a cluster is made of),
`Alpine` is a 40 MB two-minute mirror for a first look, `*` is the whole
corpus (~2.5 GB of downloads, ~12 GB on disk). Widening the list rebuilds
the mirror at the next bootstrap check. The server's memory default
(`server.resources`) is sized for the import.

## Migrations and the initializer

By default every server and client pod applies its own migration chain at
start-up, serialised across replicas by a Postgres advisory lock: one
migrates, the rest wait and find nothing to do. This works for Helm, Flux
and Argo CD with no extra configuration.

`initializer.enabled: true` moves that to two `pre-install`/`pre-upgrade`
hook Jobs (the server image with `MIGRATE_EXIT_AFTER=true`, then the
client's), and the app pods skip it. Do note:

- **Everything the Jobs read must exist before the release does.** A Helm
  hook runs before the chart's own Secrets and before the bundled
  StatefulSet, so the initializer requires an external database
  (`postgresql.enabled: false`, `database.existingSecret.name`) and the
  application secrets from `secrets.existingSecret.name`. The render fails
  otherwise.
- **The Jobs run on every sync.** Argo CD runs `pre-install` hooks as a
  `PreSync` step and re-runs them each sync, which is safe because the
  chain no-ops when the database is current. If your team disables Helm
  hooks in Argo CD, leave the initializer off.

## Sign-in

Local username/password is on by default (`auth.local.*`); the first admin
is created at start-up and must change the password on first login. Add
`auth.oidc.*` for any OpenID Connect provider (callback
`<externalUrl>/api/auth/callback/oidc`), or `auth.github.*` /
`auth.google.*`. `auth.local.enabled: false` hides the form once your
identity provider works; the render refuses a configuration with no
sign-in method at all. Locked out:

```sh
kubectl -n stackradar exec deploy/stackradar-client -- node scripts/admin-reset-password.mjs admin@stackradar.local
```

The local sign-in's per-address rate limit is in-process; with more than
one client replica, rate-limit `POST /api/auth/local` at the ingress.

## Reaching it

Port-forward (the default; NOTES prints the commands), `ingress.*` or
`httpRoute.*` — never both. Both route `/` to the client; `exposeApi: true`
adds `/v1` to the server for uploading SBOMs from outside the cluster (the
bundled scanner needs no route). `externalUrl` pins the browser-facing URL
when it cannot be derived from the hostname.

## OpenShift compatibility

The chart targets parity with OpenShift's `restricted-v2` SCC and the Pod
Security Admission `restricted` profile. Every pod ships with
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`,
`readOnlyRootFilesystem: true`, no host namespaces, no ports below 1024 and
no `NodePort` default. OpenShift assigns UIDs per namespace, so null the
pod-level contexts and let the SCC pick them:

```yaml
server:
  podSecurityContext: ~
client:
  podSecurityContext: ~
postgresql:
  podSecurityContext: ~
```

## Upgrading

```sh
helm upgrade stackradar oci://ghcr.io/lockdep/helm-charts/stackradar \
  --namespace stackradar --version <version> -f my-values.yaml
```

A `helm upgrade` with no value changes changes nothing: no Secret is
rewritten, no key rotates, and the start-up migration finds nothing to do.
Image tags default to the chart's `appVersion`; a tag from another major is
refused by the render.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth.github.clientId | string | `""` |  |
| auth.github.clientSecret | string | `""` |  |
| auth.github.existingSecret.clientIdKey | string | `"client-id"` |  |
| auth.github.existingSecret.clientSecretKey | string | `"client-secret"` |  |
| auth.github.existingSecret.name | string | `""` |  |
| auth.google.clientId | string | `""` |  |
| auth.google.clientSecret | string | `""` |  |
| auth.google.existingSecret.clientIdKey | string | `"client-id"` |  |
| auth.google.existingSecret.clientSecretKey | string | `"client-secret"` |  |
| auth.google.existingSecret.name | string | `""` |  |
| auth.local.adminEmail | string | `"admin@stackradar.local"` |  |
| auth.local.adminPassword | string | `"admin"` | Used exactly once: the first login forces a change. Read from `secrets.existingSecret` (`adminPasswordKey`) when that is set. |
| auth.local.enabled | bool | `true` | Local username/password sign-in. The first admin is created at start-up with the email and password below and must change the password on first login. `false` hides the form once an identity provider below works. |
| auth.oidc.adminGroup | string | `""` | Members of this group (in `groupsClaim`) are platform admins, re-evaluated on every sign-in. Empty: admins are managed in StackRadar only. |
| auth.oidc.clientId | string | `""` |  |
| auth.oidc.clientSecret | string | `""` |  |
| auth.oidc.existingSecret.clientIdKey | string | `"client-id"` |  |
| auth.oidc.existingSecret.clientSecretKey | string | `"client-secret"` |  |
| auth.oidc.existingSecret.name | string | `""` | Name of an existing Secret holding the client id and secret. |
| auth.oidc.groupsClaim | string | `""` | The claim that carries groups. Empty: `groups`. |
| auth.oidc.issuer | string | `""` |  |
| auth.oidc.name | string | `""` | Button label ("Continue with Keycloak"). Empty: "Single sign-on". |
| auth.oidc.scope | string | `""` | Scopes to request. Empty: the provider default (`openid email profile`). |
| client.additionalVolumeMounts | list | `[]` |  |
| client.additionalVolumes | list | `[]` |  |
| client.affinity | object | `{}` |  |
| client.annotations | object | `{}` |  |
| client.args | list | `[]` |  |
| client.autoscaling.annotations | object | `{}` |  |
| client.autoscaling.behavior | object | `{}` |  |
| client.autoscaling.enabled | bool | `false` |  |
| client.autoscaling.maxReplicas | int | `3` |  |
| client.autoscaling.minReplicas | int | `1` |  |
| client.autoscaling.targetCPUUtilizationPercentage | int | `70` |  |
| client.autoscaling.targetMemoryUtilizationPercentage | string | `nil` |  |
| client.command | list | `[]` |  |
| client.deployment.strategy.type | string | `"RollingUpdate"` |  |
| client.extraContainers | list | `[]` |  |
| client.extraEnv | list | `[]` | Don't set chart-managed variables (DATABASE_URL, STACKRADAR_EDITION, MIGRATE_*, EXPRESS_API_URL, INTERNAL_SERVICE_KEY, AUTH_*). |
| client.extraEnvFrom | list | `[]` |  |
| client.image.pullPolicy | string | `"IfNotPresent"` |  |
| client.image.registry | string | `""` |  |
| client.image.repository | string | `"lockdep/stackradar-client"` |  |
| client.image.tag | string | `""` | Tag name or `sha256:<digest>`. Defaults to the chart's `appVersion`. |
| client.initContainers | list | `[]` |  |
| client.nextCacheSizeLimit | string | `"512Mi"` | Next.js writes its image-optimiser / ISR cache here at runtime. |
| client.nodeSelector | object | `{}` |  |
| client.pdb.enabled | bool | `false` |  |
| client.pdb.maxUnavailable | string | `nil` |  |
| client.pdb.minAvailable | int | `1` |  |
| client.podAnnotations | object | `{}` |  |
| client.podLabels | object | `{}` |  |
| client.podSecurityContext.fsGroup | int | `1001` |  |
| client.podSecurityContext.runAsGroup | int | `1001` |  |
| client.podSecurityContext.runAsNonRoot | bool | `true` |  |
| client.podSecurityContext.runAsUser | int | `1001` |  |
| client.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| client.priorityClassName | string | `""` |  |
| client.probes.liveness.failureThreshold | int | `3` |  |
| client.probes.liveness.initialDelaySeconds | int | `0` |  |
| client.probes.liveness.periodSeconds | int | `10` |  |
| client.probes.liveness.successThreshold | int | `1` |  |
| client.probes.liveness.timeoutSeconds | int | `5` |  |
| client.probes.readiness.failureThreshold | int | `3` |  |
| client.probes.readiness.initialDelaySeconds | int | `0` |  |
| client.probes.readiness.periodSeconds | int | `5` |  |
| client.probes.readiness.successThreshold | int | `1` |  |
| client.probes.readiness.timeoutSeconds | int | `5` |  |
| client.probes.startup.failureThreshold | int | `60` |  |
| client.probes.startup.initialDelaySeconds | int | `5` |  |
| client.probes.startup.periodSeconds | int | `10` |  |
| client.probes.startup.successThreshold | int | `1` |  |
| client.probes.startup.timeoutSeconds | int | `5` |  |
| client.replicaCount | int | `1` | Number of replicas. NOTE: the local sign-in's per-address rate limit is in-process; with more than one replica put a rate limit on `/api/auth/local` at the ingress. |
| client.resources.limits.memory | string | `"512Mi"` |  |
| client.resources.requests.cpu | string | `"100m"` |  |
| client.resources.requests.memory | string | `"256Mi"` |  |
| client.revisionHistoryLimit | int | `5` |  |
| client.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| client.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| client.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| client.securityContext.runAsNonRoot | bool | `true` |  |
| client.securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| client.service.annotations | object | `{}` |  |
| client.service.nodePort | string | `nil` |  |
| client.service.port | int | `3000` |  |
| client.service.type | string | `"ClusterIP"` |  |
| client.terminationGracePeriodSeconds | int | `30` |  |
| client.tmpSizeLimit | string | `"256Mi"` |  |
| client.tolerations | list | `[]` |  |
| client.topologySpreadConstraints | list | `[]` |  |
| database.existingSecret.caCertKey | string | `""` | Optional key in the same Secret holding the PEM of the CA to verify the database server against (`DATABASE_CA_CERT`, for `sslmode=verify-ca` / `verify-full`). Empty: not mounted. |
| database.existingSecret.name | string | `""` | Name of an existing Secret holding the connection string. When set, `database.url` must be empty. |
| database.existingSecret.urlKey | string | `"url"` | Key in that Secret holding the connection string. |
| database.url | string | `""` | Connection string for an external PostgreSQL, used when `postgresql.enabled` is false. Both apps read it (the client keeps its Auth.js tables in the `auth` schema of the same database). Must carry an explicit `sslmode` — `require` for a managed database, `prefer` for one on a private network — because the server refuses a production URL that says nothing about TLS. Stored in a chart-managed Secret; prefer `existingSecret` for anything beyond evaluation. |
| enableServiceLinks | bool | `false` |  |
| externalUrl | string | `""` | The URL users open the UI at, e.g. `https://stackradar.example.com`. It is what links in the UI point to (`APP_URL`) and what the session cookie is issued for (`AUTH_URL`). Empty: derived from `ingress.hostname` / `httpRoute.hostnames[0]` when either is enabled, otherwise the install is reached by port-forward and the client trusts the Host header instead. |
| extraObjects | list | `[]` | Extra manifests, rendered through `tpl`. |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` | Gateway API alternative to the Ingress; the two are mutually exclusive. Requires `parentRefs`. |
| httpRoute.exposeApi | bool | `false` |  |
| httpRoute.hostnames[0] | string | `"stackradar.example.com"` |  |
| httpRoute.labels | object | `{}` |  |
| httpRoute.parentRefs | list | `[]` |  |
| image.pullSecrets | list | `[]` | Pull secrets for every chart-managed pod (the scanner subchart has its own `imagePullSecrets`). |
| image.registry | string | `"ghcr.io"` | Default container image registry. Overridable per component. |
| ingress.annotations | object | `{}` |  |
| ingress.enabled | bool | `false` | Routes `/` to the client. The server's public API (`/v1`, what a scanner talks to) is only exposed when `exposeApi` is set; the bundled scanner reaches the server in-cluster and needs no Ingress. |
| ingress.exposeApi | bool | `false` | Also route `/v1` to the server, for uploading SBOMs from outside the cluster. |
| ingress.hostname | string | `"stackradar.example.com"` |  |
| ingress.ingressClassName | string | `""` |  |
| ingress.labels | object | `{}` |  |
| ingress.tls | list | `[]` |  |
| initializer.annotations | object | `{}` | Annotations on the Job. Merged with (and may override) the chart's `helm.sh/hook*` annotations. |
| initializer.backoffLimit | int | `3` |  |
| initializer.enabled | bool | `false` |  |
| initializer.initContainers | list | `[]` |  |
| initializer.nodeSelector | object | `{}` |  |
| initializer.podAnnotations | object | `{}` |  |
| initializer.resources.limits.memory | string | `"512Mi"` |  |
| initializer.resources.requests.cpu | string | `"100m"` |  |
| initializer.resources.requests.memory | string | `"256Mi"` |  |
| initializer.tolerations | list | `[]` |  |
| logLevel | string | `"info"` | `LOG_LEVEL` for the server, worker and client. |
| metrics.prometheusRule.enabled | bool | `false` | Create the OSV-mirror alert rules (mirror stale, not initialised, sync failing, lag high, metrics unavailable). |
| metrics.prometheusRule.labels | object | `{}` |  |
| metrics.prometheusRule.namespace | string | `""` |  |
| metrics.serviceMonitor.enabled | bool | `false` | Create a Prometheus Operator ServiceMonitor scraping the server's `/metrics`. |
| metrics.serviceMonitor.interval | string | `"30s"` |  |
| metrics.serviceMonitor.labels | object | `{}` |  |
| metrics.serviceMonitor.namespace | string | `""` | Namespace for the ServiceMonitor. Empty: the release namespace. |
| metrics.serviceMonitor.scrapeTimeout | string | `"10s"` |  |
| nameOverride | string | `""` |  |
| networkPolicy.enabled | bool | `false` | Default-deny ingress to the server, client and worker pods, then allow: client → server, scanner → server, `ingressFrom` → client (and → server when `ingress.exposeApi`), `metricsFrom` → server `/metrics`. Egress: DNS, the database, TCP 443 anywhere (feeds, registries) plus `extraEgress`. |
| networkPolicy.extraEgress | list | `[]` | Extra egress rules for every chart-managed pod, in `spec.egress` shape (an external database on a non-5432 port, a proxy, a registry on 80). |
| networkPolicy.ingressFrom | list | `[]` | Peers (NetworkPolicy `from` entries) allowed to reach the UI, i.e. your ingress controller: `- namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}`. Empty: any source may reach the client port. |
| networkPolicy.metricsFrom | list | `[]` | Peers allowed to scrape the server's `/metrics`. Empty: none. |
| nodeSelector | object | `{}` | Node selector applied to all chart-managed pods. Replaced entirely by a component-level `nodeSelector` when one is set to a non-empty value. |
| postgresql.affinity | object | `{}` |  |
| postgresql.args | list | `[]` | Extra `postgres` server arguments, e.g. `["-c", "shared_buffers=512MB"]`. |
| postgresql.auth.database | string | `"stackradar"` |  |
| postgresql.auth.existingSecret.name | string | `""` | Name of an existing Secret holding the password. When set, `password` must be left at its default. |
| postgresql.auth.existingSecret.passwordKey | string | `"password"` | Key in that Secret holding the password. |
| postgresql.auth.password | string | `"stackradar-fixture-db-password"` | The role's password, stored in a chart-managed Secret. PUBLIC FIXTURE: the same on every install that leaves it. Set your own (`openssl rand -hex 24`; keep it URL-safe, it is interpolated into `DATABASE_URL`) or reference an `existingSecret`. Postgres sets the password when it initialises the volume, so change it before the first install or change it in Postgres afterwards. |
| postgresql.auth.username | string | `"stackradar"` | Database and role name; both apps connect as this user. |
| postgresql.enabled | bool | `true` | Deploy the bundled PostgreSQL. Set to false and configure `database.*` for your own; setting both fails the render. |
| postgresql.image.digest | string | `"sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873"` | Image digest, so every install of this chart version runs the same bytes. The multi-arch index digest of `postgres:18-alpine` on 10 Oct 2026. |
| postgresql.image.pullPolicy | string | `"IfNotPresent"` |  |
| postgresql.image.registry | string | `"docker.io"` | Override `image.registry` for PostgreSQL. The official image lives on Docker Hub. |
| postgresql.image.repository | string | `"library/postgres"` |  |
| postgresql.image.tag | string | `"18-alpine"` | Tag name. The chart pins the image by `digest` as well; to run a different image clear the digest too. |
| postgresql.nodeSelector | object | `{}` |  |
| postgresql.persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| postgresql.persistence.annotations | object | `{}` | Extra annotations on the volume claim template. |
| postgresql.persistence.size | string | `"10Gi"` | Size of the data volume, created from `volumeClaimTemplates`. The StatefulSet retains it on deletion and it carries `helm.sh/resource-policy: keep`: `helm uninstall` never deletes data. |
| postgresql.persistence.storageClassName | string | `""` | StorageClass for the data volume. Empty: the cluster default. |
| postgresql.podAnnotations | object | `{}` |  |
| postgresql.podLabels | object | `{}` |  |
| postgresql.podSecurityContext | object | `{"fsGroup":70,"runAsGroup":70,"runAsNonRoot":true,"runAsUser":70,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. uid/gid 70 is `postgres` in the Alpine image; `fsGroup` makes the volume writable. On OpenShift set it to `~`. |
| postgresql.priorityClassName | string | `""` |  |
| postgresql.probes.liveness.failureThreshold | int | `6` |  |
| postgresql.probes.liveness.initialDelaySeconds | int | `30` |  |
| postgresql.probes.liveness.periodSeconds | int | `10` |  |
| postgresql.probes.liveness.successThreshold | int | `1` |  |
| postgresql.probes.liveness.timeoutSeconds | int | `5` |  |
| postgresql.probes.readiness.failureThreshold | int | `6` |  |
| postgresql.probes.readiness.initialDelaySeconds | int | `5` |  |
| postgresql.probes.readiness.periodSeconds | int | `10` |  |
| postgresql.probes.readiness.successThreshold | int | `1` |  |
| postgresql.probes.readiness.timeoutSeconds | int | `5` |  |
| postgresql.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Memory request and limit (no CPU limit, by house rule: CPU is compressible and a limit only throttles). The default-list OSV mirror is low single-digit GB on disk; the import is the memory peak. |
| postgresql.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| postgresql.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| postgresql.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| postgresql.securityContext.runAsNonRoot | bool | `true` |  |
| postgresql.securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| postgresql.shmSizeLimit | string | `"256Mi"` | Size limit of the `/dev/shm` memory-backed volume. Kubernetes' default 64 MiB is too small for Postgres' parallel workers on a large mirror. |
| postgresql.tolerations | list | `[]` |  |
| scanner.enabled | bool | `true` |  |
| scanner.networkPolicy.enabled | bool | `true` | The subchart's own policy (ingress: kubelet probes only; egress: DNS, the API server, TCP 443). When on, this chart adds the one rule it lacks — egress to the server pods — so the scanner can report in-cluster. |
| scanner.stackradar.apiKey | string | `"stackradar-fixture-bootstrap-scanner-key"` | The key the scanner authenticates with and the server accepts for that cluster (`BOOTSTRAP_CLUSTER_API_KEY`). PUBLIC FIXTURE: with it, any pod in the cluster that can reach the server Service can upload SBOMs as the local cluster. Generate your own with `openssl rand -hex 32`. The subchart renders both into the Secret `<release>-stackradar-scanner`, which the server reads too. |
| scanner.stackradar.apiUrl | string | `"http://{{ .Release.Name }}-server.{{ .Release.Namespace }}.svc:8080"` | Where the scanner reports to. The default is this release's server Service, rendered by the subchart through `tpl`. Override for a mesh that terminates TLS; the chart checks that a default-shaped value still names the real Service when `fullnameOverride` or `server.service.port` change. |
| scanner.stackradar.clusterId | string | `"8f6b0b7a-0c1e-4f6e-9a4b-2f3d1c0e5a71"` | The cluster id the scanner reports as and the server creates at start-up (`BOOTSTRAP_CLUSTER_ID`). A UUID: `uuidgen | tr A-Z a-z`. |
| scanner.stackradar.existingSecret | string | `""` | Name of an existing Secret with keys `cluster-id` and `api-key` (overridable below) instead of the inline pair; the server reads the same Secret. When set, `clusterId` and `apiKey` must be left at their defaults. |
| scanner.stackradar.existingSecretKeyApiKey | string | `""` |  |
| scanner.stackradar.existingSecretKeyClusterId | string | `""` |  |
| secrets.apiKeyEncryptionKey | string | `"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"` | Encrypts scanner keys at rest so an admin can reveal them. 64 hex characters: `openssl rand -hex 32`. Changing it later makes the stored keys unreadable, so set it once. |
| secrets.authSecret | string | `"stackradar-fixture-auth-secret-change-me"` | Signs the session cookie. Generate with `openssl rand -base64 32`. |
| secrets.existingSecret.adminPasswordKey | string | `"admin-password"` |  |
| secrets.existingSecret.apiKeyEncryptionKeyKey | string | `"api-key-encryption-key"` |  |
| secrets.existingSecret.authSecretKey | string | `"auth-secret"` |  |
| secrets.existingSecret.internalServiceKeyKey | string | `"internal-service-key"` |  |
| secrets.existingSecret.name | string | `""` | Name of an existing Secret holding all three (and the bootstrap admin password when `auth.local.enabled`). When set, the inline values above must be left at their defaults. |
| secrets.internalServiceKey | string | `"stackradar-fixture-internal-service-key"` | Shared between the client and the server (`X-Internal-Key` on every BFF → server call). Generate with `openssl rand -hex 32`. |
| server.additionalVolumeMounts | list | `[]` |  |
| server.additionalVolumes | list | `[]` |  |
| server.affinity | object | `{}` |  |
| server.annotations | object | `{}` | Annotations on the Deployment. |
| server.args | list | `[]` |  |
| server.autoscaling.annotations | object | `{}` |  |
| server.autoscaling.behavior | object | `{}` |  |
| server.autoscaling.enabled | bool | `false` |  |
| server.autoscaling.maxReplicas | int | `5` |  |
| server.autoscaling.minReplicas | int | `1` |  |
| server.autoscaling.targetCPUUtilizationPercentage | int | `70` |  |
| server.autoscaling.targetMemoryUtilizationPercentage | string | `nil` |  |
| server.command | list | `[]` |  |
| server.deployment.strategy.rollingUpdate.maxSurge | int | `0` |  |
| server.deployment.strategy.rollingUpdate.maxUnavailable | int | `1` |  |
| server.deployment.strategy.type | string | `"RollingUpdate"` |  |
| server.extraContainers | list | `[]` |  |
| server.extraEnv | list | `[]` | Extra env for the server (and the worker and sync Jobs in `split`). Don't set chart-managed variables (DATABASE_URL, STACKRADAR_EDITION, TOPOLOGY, MIGRATE_*, APP_URL, INTERNAL_SERVICE_KEY, API_KEY_ENCRYPTION_KEY, BOOTSTRAP_*, OSV_ECOSYSTEMS, *_CRON, ARTIFACT_HUB_SYNC_ENABLED). |
| server.extraEnvFrom | list | `[]` |  |
| server.image.pullPolicy | string | `"IfNotPresent"` |  |
| server.image.registry | string | `""` | Override `image.registry` for the server. |
| server.image.repository | string | `"lockdep/stackradar-server"` |  |
| server.image.tag | string | `""` | Tag name or `sha256:<digest>`. Defaults to the chart's `appVersion`. |
| server.initContainers | list | `[]` |  |
| server.nodeOptions | string | `"--max-old-space-size=1536"` | `NODE_OPTIONS`. The heap ceiling has to cover the OSV import in `monolith` topology (the default list peaks well under this); the cloud's HTTP-only server runs with 768. |
| server.nodeSelector | object | `{}` |  |
| server.pdb.enabled | bool | `false` |  |
| server.pdb.maxUnavailable | string | `nil` |  |
| server.pdb.minAvailable | int | `1` |  |
| server.podAnnotations | object | `{}` |  |
| server.podLabels | object | `{}` |  |
| server.podSecurityContext | object | `{"fsGroup":1001,"runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seccompProfile":{"type":"RuntimeDefault"}}` | uid/gid 1001 is the image's user. On OpenShift set it to `~`. |
| server.priorityClassName | string | `""` |  |
| server.probes.liveness.failureThreshold | int | `3` |  |
| server.probes.liveness.initialDelaySeconds | int | `0` |  |
| server.probes.liveness.periodSeconds | int | `10` |  |
| server.probes.liveness.successThreshold | int | `1` |  |
| server.probes.liveness.timeoutSeconds | int | `5` |  |
| server.probes.readiness.failureThreshold | int | `3` |  |
| server.probes.readiness.initialDelaySeconds | int | `0` |  |
| server.probes.readiness.periodSeconds | int | `5` |  |
| server.probes.readiness.successThreshold | int | `1` |  |
| server.probes.readiness.timeoutSeconds | int | `5` |  |
| server.probes.startup | object | `{"failureThreshold":60,"initialDelaySeconds":5,"periodSeconds":10,"successThreshold":1,"timeoutSeconds":5}` | Startup budget covers migrations on first install and on upgrades: 60 × 10 s = 10 min. For a long backfill migration raise it and pass `helm upgrade --timeout`, since Helm's 5-minute default fires first. |
| server.replicaCount | int | `1` | Number of replicas. More than one is safe: the job queue claims with `SKIP LOCKED` and every sync takes an advisory lock. |
| server.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"250m","memory":"1Gi"}}` | Memory sized for `monolith`: the OSV import and syft runs happen in this pod. The steady state is a few hundred MB. No CPU limit (house rule). |
| server.revisionHistoryLimit | int | `5` |  |
| server.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| server.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| server.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| server.securityContext.runAsNonRoot | bool | `true` |  |
| server.securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| server.service.annotations | object | `{}` |  |
| server.service.nodePort | string | `nil` |  |
| server.service.port | int | `8080` | The port the Service listens on; the container listens on 3001. The scanner subchart's default `stackradar.apiUrl` names this port. |
| server.service.type | string | `"ClusterIP"` |  |
| server.terminationGracePeriodSeconds | int | `120` | Lets in-flight uploads finish and, in `monolith`, a running scan job drain. |
| server.tmpSizeLimit | string | `"8Gi"` | Size limit of the `/tmp` scratch volume: OSV archives land there during the import, and in `monolith` topology syft unpacks images there. |
| server.tolerations | list | `[]` |  |
| server.topologySpreadConstraints | list | `[]` |  |
| serviceAccount.annotations | object | `{}` | Annotations on the created ServiceAccount. |
| serviceAccount.create | bool | `true` | Whether to create a ServiceAccount for the server, client and worker pods. None of them talks to the Kubernetes API; the token is never mounted. The scanner subchart creates its own, which does. |
| serviceAccount.name | string | `""` | Name of the ServiceAccount. Defaults to the release fullname when empty. Provide a custom name and set `create: false` to use a ServiceAccount you manage. |
| sync.artifactHub.activeDeadlineSeconds | int | `1800` |  |
| sync.artifactHub.backoffLimit | int | `2` |  |
| sync.artifactHub.resources.limits.memory | string | `"1Gi"` |  |
| sync.artifactHub.resources.requests.cpu | string | `"250m"` |  |
| sync.artifactHub.resources.requests.memory | string | `"256Mi"` |  |
| sync.artifactHub.schedule | string | `"15 2 * * *"` | Only rendered / scheduled when `vulnerabilityData.artifactHubSync.enabled`. |
| sync.epss.activeDeadlineSeconds | int | `1800` |  |
| sync.epss.backoffLimit | int | `1` |  |
| sync.epss.resources.limits.memory | string | `"512Mi"` |  |
| sync.epss.resources.requests.cpu | string | `"100m"` |  |
| sync.epss.resources.requests.memory | string | `"128Mi"` |  |
| sync.epss.schedule | string | `"15 6 * * *"` |  |
| sync.failedJobsHistoryLimit | int | `3` |  |
| sync.kev.activeDeadlineSeconds | int | `1800` |  |
| sync.kev.backoffLimit | int | `1` |  |
| sync.kev.resources.limits.memory | string | `"256Mi"` |  |
| sync.kev.resources.requests.cpu | string | `"50m"` |  |
| sync.kev.resources.requests.memory | string | `"64Mi"` |  |
| sync.kev.schedule | string | `"15 7 * * *"` |  |
| sync.nodeSelector | object | `{}` |  |
| sync.osv.activeDeadlineSeconds | int | `5400` |  |
| sync.osv.backoffLimit | int | `2` |  |
| sync.osv.resources.limits.memory | string | `"1Gi"` |  |
| sync.osv.resources.requests.cpu | string | `"250m"` |  |
| sync.osv.resources.requests.memory | string | `"256Mi"` |  |
| sync.osv.schedule | string | `"0 * * * *"` | Incremental OSV sync. |
| sync.osvBootstrap.activeDeadlineSeconds | int | `28800` |  |
| sync.osvBootstrap.backoffLimit | int | `0` |  |
| sync.osvBootstrap.resources.limits.memory | string | `"2Gi"` |  |
| sync.osvBootstrap.resources.requests.cpu | string | `"500m"` |  |
| sync.osvBootstrap.resources.requests.memory | string | `"512Mi"` |  |
| sync.osvBootstrap.schedule | string | `"0 */12 * * *"` | Rebuilds the mirror when there is no complete generation (a fresh install, a restored database); a no-op otherwise. |
| sync.podAnnotations | object | `{}` |  |
| sync.successfulJobsHistoryLimit | int | `3` | Applied to every CronJob in `split` topology. |
| sync.tolerations | list | `[]` |  |
| sync.ttlSecondsAfterFinished | int | `604800` |  |
| tolerations | list | `[]` | Tolerations applied to all chart-managed pods. Replaced entirely by a component-level `tolerations` when one is set to a non-empty value. |
| topology | string | `"monolith"` | `monolith` (default): one `server` Deployment runs the API, the job worker and the in-process schedule for the OSV / EPSS / KEV syncs; the install is `server` + `client` + the scanner. `split`: the server is HTTP-only, the worker is its own Deployment (`worker.*`) and the syncs are CronJobs (`sync.*`) — the cloud's shape, for installs that want to scale the pieces separately. Setting `worker.*` knobs in `monolith` fails the render rather than being ignored. |
| vulnerabilityData.artifactHubSync.enabled | bool | `false` | Mirror Artifact Hub's package index nightly, for chart attribution and upgrade recommendations. Off by default: ~25 MB a night and a 1 GB memory peak that a single-cluster dashboard does not need. |
| vulnerabilityData.osvEcosystems | string | `""` | Comma-separated OSV directory names the mirror carries (`Alpine,Debian,Red Hat,npm`; case-sensitive, spaces included). Empty: the community default — the base images and package managers a cluster is made of. `*` is the whole corpus (~2.5 GB of downloads, ~12 GB on disk). `Alpine` alone is a two-minute, 40 MB mirror for a first look. Widening the list later rebuilds the mirror at the next bootstrap check. |
| worker | object | `{"affinity":{},"annotations":{},"autoscaling":{"annotations":{},"behavior":{},"enabled":false,"maxReplicas":5,"minReplicas":1,"targetCPUUtilizationPercentage":70,"targetMemoryUtilizationPercentage":null},"extraEnv":[],"extraEnvFrom":[],"gomemlimit":"1GiB","nodeSelector":{},"pdb":{"enabled":false,"maxUnavailable":null,"minAvailable":1},"podAnnotations":{},"podLabels":{},"priorityClassName":"","replicaCount":1,"resources":{"limits":{"memory":"1536Mi"},"requests":{"cpu":"100m","memory":"768Mi"}},"revisionHistoryLimit":5,"terminationGracePeriodSeconds":900,"tmpSizeLimit":"8Gi","tolerations":[],"topologySpreadConstraints":[]}` | The job worker. Only rendered when `topology: split`; in `monolith` the server runs it and setting anything here fails the render. |
| worker.gomemlimit | string | `"1GiB"` | syft runs inside this pod; `GOMEMLIMIT` reaches it through the environment and keeps its heap under the container limit. |
| worker.terminationGracePeriodSeconds | int | `900` | Long: a nightly platform scan in progress should finish, not be killed mid-image. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
