# Upgrading the `stackradar` chart

Chart-level breaking changes, by chart version. Application-level changes
(schema migrations, behaviour) are in the
[StackRadar release notes](https://github.com/lockdep/stackradar/releases);
read those for every version you skip past, not just the target one.

## 0.2.0

No chart-level breaking change: no value was renamed, removed or given a new
default, so `helm upgrade` with the values you already set is enough.

- `appVersion` moves from 0.1.0 to 0.2.0. The app release carries two
  additive schema migrations (new nullable columns), which the server
  applies at start-up as usual; see the
  [0.2.0 release notes](https://github.com/lockdep/stackradar/releases/tag/v0.2.0).
- The bundled `stackradar-scanner` subchart moves from 0.5.0 to 0.7.0. Its
  values are unchanged; it is now licensed under Apache-2.0 and reports the
  names of each container's `imagePullSecrets` so the Coverage card can
  name the fix for a private registry.

## 0.1.0

The first version.
