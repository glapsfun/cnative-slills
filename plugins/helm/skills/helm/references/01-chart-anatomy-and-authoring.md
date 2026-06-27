# Chart anatomy and authoring

## Directory layout

`helm create mychart` scaffolds the canonical structure. Know what each piece is for:

```
mychart/
├── Chart.yaml            # chart metadata (required)
├── values.yaml           # default configuration values (the public API of the chart)
├── values.schema.json    # JSON Schema validating values (optional but recommended)
├── .helmignore           # patterns excluded when packaging
├── charts/               # vendored subchart archives / dependency charts
├── crds/                 # CustomResourceDefinitions, installed before templates, never re-templated
├── templates/
│   ├── _helpers.tpl      # named templates (partials); files starting with _ are not rendered as manifests
│   ├── NOTES.txt         # post-install usage notes (templated, printed after install)
│   ├── deployment.yaml
│   ├── service.yaml
│   └── tests/            # `helm test` hooks
└── README.md
```

`helm create` already wires labels, a ServiceAccount, an HPA, an Ingress, and a probes-ready Deployment to `values.yaml`. **Start from it and delete what you don't need** rather than authoring from blank — the scaffold embodies many best practices.

## Chart.yaml

```yaml
apiVersion: v2            # v2 = Helm 3 charts. v1 is legacy Helm 2 — use v2 for anything new.
name: mychart
description: A Helm chart for my app
type: application         # or "library" (template-only, not installable)
version: 1.2.3            # SemVer of the CHART itself — bump on every chart change
appVersion: "2.4.1"       # version of the APP being deployed (string; quote it)
kubeVersion: ">=1.27.0-0" # optional: constrain target cluster versions
dependencies:
  - name: postgresql
    version: "15.5.x"     # pin dependency versions
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled   # toggle the subchart via values
    alias: db                        # optional rename
```

Two distinct versions trip people up: **`version` is the chart's SemVer** (bump it for any chart change, since this is what users pin and what triggers updates), while **`appVersion` is the deployed application's version** (informational; quote it so `1.10` isn't coerced to `1.1`).

## values.yaml — the chart's public API

`values.yaml` is the contract users configure against. Design it deliberately:

- **camelCase keys**, starting lowercase: `imagePullPolicy`, not `image-pull-policy` (hyphens are illegal in template variable access) or `ImagePullPolicy` (uppercase is reserved for built-ins like `.Release`).
- **Favor flat over deeply nested** where reasonable — every nesting level is another nil-check in templates and another `--set a.b.c.d` for users. Nest when grouping a cohesive block (e.g. `resources:`, `image:`).
- **Prefer maps over arrays** for things users override, because `--set servers.foo.port=80` works but `--set servers[0].port=80` is awkward and `--set` *replaces* whole arrays.
- **Document every value** with a `#` comment beginning with the key name, so it's greppable: `# replicaCount is the number of pod replicas`.

## values.schema.json — validate inputs

A JSON Schema file enforces types and required fields at install/template time, turning "silent wrong behavior" into an early, clear error.

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1 },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": { "type": "string" },
        "tag": { "type": "string" },
        "pullPolicy": { "enum": ["Always", "IfNotPresent", "Never"] }
      }
    }
  }
}
```

Helm validates the merged values against this on `install`, `upgrade`, `lint`, and `template`. It's the cleanest way to fail fast on bad input.

## Dependencies and subcharts

```bash
helm dependency update ./mychart    # resolve Chart.yaml deps into charts/ and write Chart.lock
helm dependency build ./mychart     # rebuild charts/ from an existing Chart.lock
helm dependency list ./mychart
```

- **Pin versions** in `Chart.yaml` and commit `Chart.lock` for reproducibility.
- **`condition`** (e.g. `postgresql.enabled`) lets users toggle a subchart on/off from values; **`tags`** group several.
- A parent chart can **override subchart values** by nesting under the subchart name: `postgresql: { auth: { username: app } }`.
- **`alias`** lets you include the same chart twice under different names.
- **Global values** (`.Values.global.*`) are visible to the parent and all subcharts — the way to share config like `global.imageRegistry`.

## Library charts

`type: library` charts contain only named templates (`define`) and ship no manifests. Other charts depend on them and `include` their helpers — the DRY way to share templating across many app charts. They are not installable on their own.

## Hooks

Annotations turn a template into a lifecycle hook that runs at a defined phase:

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "5"                       # ordering within a phase (ascending)
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

Common phases: `pre-install`, `post-install`, `pre-upgrade`, `post-upgrade`, `pre-delete`, `post-delete`, `test`. Use them for DB migrations, schema setup, and smoke tests. Set a sane `hook-delete-policy` so old hook Jobs don't accumulate or block re-runs (`before-hook-creation` deletes the prior one first).

## Packaging and distribution

```bash
helm package ./mychart                    # produces mychart-1.2.3.tgz
helm package ./mychart --sign --key ...   # provenance signing
helm repo index .                          # generate/update index.yaml for an HTTP repo
helm push mychart-1.2.3.tgz oci://registry.example.com/charts   # OCI registry (Helm 3.8+)
```

OCI registries are now the recommended distribution mechanism; classic HTTP repos (`index.yaml`) still work. See `references/06-discovery-and-repos.md`.
