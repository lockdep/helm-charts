# helm-charts

Helm charts for [StackRadar](https://stackradar.io): what is running in your
Kubernetes cluster, which of it is vulnerable, and what to move to.

| Chart | What it installs |
|---|---|
| [`stackradar`](charts/stackradar) | StackRadar Community Edition: the server, the UI, a bundled Postgres and the scanner, already scanning the cluster it lands in. |

The scanner on its own (for the cloud at app.stackradar.io, or a second
cluster) is published from its own repository as
`oci://ghcr.io/lockdep/charts/stackradar-scanner`.

## Usage

Charts are published as OCI artifacts to GitHub Container Registry.
This is the preferred way to consume them:

```shell
helm install stackradar oci://ghcr.io/lockdep/helm-charts/stackradar \
  --namespace stackradar --create-namespace
```

Alternatively, the charts remain available from the classic Helm repository:

```shell
helm repo add lockdep https://lockdep.github.io/helm-charts

helm search repo lockdep
```

## Verifying charts

Charts are signed with GPG. Signatures are published as `.prov` files alongside
the chart, in both the OCI registry and the Helm repository.
Refer to [Helm Provenance and Integrity](https://helm.sh/docs/topics/provenance/) for details.

Import the signing key from [`KEYS`](KEYS) and export it to a keyring Helm can read.

```shell
curl -fsSL https://raw.githubusercontent.com/lockdep/helm-charts/main/KEYS | gpg --import

gpg --export helm@stackradar.io > /tmp/lockdep-keyring.gpg
```

> [!TIP]
> The export step is necessary because Helm only reads the legacy `pubring.gpg` format,
> which GnuPG stopped maintaining with version 2.1 (see [helm/helm#31836](https://github.com/helm/helm/issues/31836),
> [helm/helm#32281](https://github.com/helm/helm/pull/32281))

Verify at pull time:

```shell
helm pull oci://ghcr.io/lockdep/helm-charts/stackradar \
  --prov --verify --keyring /tmp/lockdep-keyring.gpg
```

`--verify` works with `helm install` and `helm upgrade` as well.

## Developing

```shell
make deps          # restore the scanner subchart from Chart.lock
make unit-test     # helm-unittest, in its pinned container
make lint          # ct lint
make kubeconform   # render every ci/*-values.yaml and validate against the Kubernetes schemas
make determinism   # render twice, diff: the chart generates nothing random
make docs          # regenerate charts/*/README.md with helm-docs
```

The charts are Apache-2.0 (see [LICENSE](LICENSE)); the application images
they deploy carry their own licences.
