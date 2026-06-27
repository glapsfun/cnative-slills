# The helm CLI and release lifecycle

A **release** is an instance of a chart installed into a cluster, tracked by Helm in a per-revision Secret (default driver) in the release namespace. Every `upgrade`/`rollback` creates a new revision.

## Core lifecycle commands

```bash
helm install my-release ./mychart -n my-ns --create-namespace
helm install my-release oci://registry/charts/mychart --version 1.2.3
helm upgrade my-release ./mychart -n my-ns -f prod.yaml
helm upgrade --install my-release ./mychart -n my-ns      # install if absent, else upgrade (idempotent — ideal for CI)
helm rollback my-release 3 -n my-ns                        # revert to revision 3
helm uninstall my-release -n my-ns                         # remove (use --keep-history to retain revision records)
```

Key flags that change behavior meaningfully:

| Flag | Effect |
|------|--------|
| `--atomic` | On failure, automatically roll back to the prior revision instead of leaving a broken/partial release. Strongly recommended for upgrades. |
| `--wait` | Block until resources are Ready (pods, PVCs, etc.) before reporting success. `--wait-for-jobs` also waits on Jobs. |
| `--timeout 5m` | How long `--wait` waits before failing. |
| `--install` | (on `upgrade`) create the release if it doesn't exist — the idempotent CI pattern. |
| `--force` | Force resource replacement via delete+recreate. Dangerous — can cause downtime; avoid unless necessary. |
| `--cleanup-on-fail` | Delete newly-created resources if an upgrade fails. |
| `--reuse-values` / `--reset-values` | Carry over the previous release's values, or reset to chart defaults. Mixing with `-f`/`--set` is a common surprise — see precedence below. |
| `-n` / `--namespace`, `--create-namespace` | Target namespace (Helm does NOT default to your kubectl namespace for all ops — be explicit). |

## Values precedence (later wins)

When the same key is set in multiple places, the **last** source wins, evaluated in this order:

1. Chart's own `values.yaml`
2. Parent chart values (for subcharts) and `global` values
3. `-f` / `--values` files, applied **left to right**
4. `--set`, `--set-string`, `--set-file`, `--set-json` (highest precedence)

Two gotchas that cause "my override didn't take effect":

- **`--set` replaces entire arrays**, it does not merge them. To change one list element you must re-supply the whole list (often easier via a `-f` file).
- On `upgrade`, if you pass neither `--reuse-values` nor `--reset-values`, Helm reuses previously-set individual values and merges your new `--set`/`-f` on top. Passing `--reset-values` drops prior overrides back to chart defaults. Know which you want.

Inspect what actually applied:

```bash
helm get values my-release -n my-ns        # user-supplied values
helm get values my-release -n my-ns -a     # all computed values (defaults + overrides)
```

## Inspection and history

```bash
helm list -n my-ns                  # releases in a namespace (-A for all namespaces)
helm status my-release -n my-ns     # current state + NOTES
helm history my-release -n my-ns    # every revision with status (deployed/superseded/failed/pending-*)
helm get manifest my-release -n my-ns   # the exact YAML Helm applied for the current revision
helm get hooks my-release -n my-ns
helm get notes my-release -n my-ns
```

`helm get manifest` is the source of truth for "what did Helm actually deploy" — far more reliable than re-rendering, because it reflects the values that were really in effect.

## Local / authoring commands

```bash
helm create mychart                 # scaffold a new chart
helm lint ./mychart --strict        # static checks; --strict promotes warnings to errors
helm template rel ./mychart         # render manifests to stdout (no cluster needed)
helm package ./mychart              # build a .tgz
helm show values ./mychart          # print a chart's default values
helm show chart ./mychart           # print Chart.yaml
```

## helm test

If the chart has templates under `templates/tests/` annotated as `helm.sh/hook: test`, run them against a live release as smoke tests:

```bash
helm test my-release -n my-ns
```

Each test is a Pod; success = the Pod completes 0. Use it to validate connectivity/health post-install.

## helm diff (plugin)

The `helm-diff` plugin previews what an upgrade would change before you apply it — invaluable in review and CI:

```bash
helm plugin install https://github.com/databus23/helm-diff
helm diff upgrade my-release ./mychart -n my-ns -f prod.yaml
```

## OCI registries

Helm 3.8+ treats OCI registries as first-class:

```bash
helm registry login registry.example.com
helm push mychart-1.2.3.tgz oci://registry.example.com/charts
helm install my-release oci://registry.example.com/charts/mychart --version 1.2.3
helm pull oci://registry.example.com/charts/mychart --version 1.2.3
```

No `helm repo add` needed for OCI — reference the `oci://` URL directly.
