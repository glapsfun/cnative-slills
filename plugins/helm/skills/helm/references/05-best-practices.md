# Chart best practices

These distill the official Helm best-practices guide plus widely-used production conventions. Verify field names against the target Kubernetes version, since API groups drift.

## Values: design the public API deliberately

- **Naming:** camelCase, lowercase first letter (`nodeSelector`, `imagePullSecrets`). Hyphens are illegal in template access; PascalCase collides with built-ins.
- **Flat over nested** where reasonable — each level is another nil-guard in templates and another `--set a.b.c`. Group cohesive blocks (`image:`, `resources:`, `service:`) but don't over-nest.
- **Maps over arrays** for user-overridable collections, because `--set` replaces whole arrays and can't address `[0]` ergonomically.
- **Quote strings; mind numeric coercion.** Unquoted `1.10`, `yes`, `on`, `1e3`, and leading-zero values get reinterpreted by YAML. Quote image tags and any string that looks numeric.
- **Document every value** with a `#` comment starting with the key, for grep-ability.
- **Ship a `values.schema.json`** to type-check and require inputs (see `01-chart-anatomy-and-authoring.md`).
- Provide **safe defaults** that install cleanly out of the box, but never default secrets/passwords to a real value — require them.

## Labels and annotations

Apply the recommended Kubernetes labels via a namespaced helper so every resource is consistent and selectable. `helm create` generates these; keep them:

```yaml
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
```

Split **selector labels** (a small, immutable subset like `name`+`instance`) from the full label set: a Deployment's `spec.selector.matchLabels` is immutable after creation, so it must not include volatile labels like `version`. `helm create` models this with separate `mychart.labels` and `mychart.selectorLabels` helpers — follow it.

## Workload hygiene (make it production-grade)

The Deployment a chart ships should set, and expose via values:

- **Resource requests and limits** (`resources:` from `toYaml .Values.resources | nindent`). Without requests, scheduling and autoscaling misbehave.
- **Liveness and readiness probes** — readiness gates traffic; liveness restarts wedged pods. Make paths/ports configurable.
- **`securityContext`** — `runAsNonRoot: true`, drop capabilities, `readOnlyRootFilesystem` where possible; both pod- and container-level.
- **Image:** never default `tag` to `latest` (breaks rollbacks and caching); default to `.Chart.AppVersion`. Make `repository`, `tag`, and `pullPolicy` configurable; support `imagePullSecrets`.
- **ServiceAccount** — create one per chart (toggleable), don't reuse `default`.
- **Roll on config change:** add a checksum annotation so a ConfigMap/Secret change triggers a pod restart:
  ```yaml
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```

## CRDs

- Put CustomResourceDefinitions in the chart's top-level **`crds/`** directory. Helm installs them **before** templates and **does not template, upgrade, or delete** them — this is intentional to avoid data loss.
- Because Helm won't upgrade CRDs, document the manual upgrade path, or manage CRDs in a separate chart/process when they change often.
- Guard resources that depend on a CRD with `.Capabilities.APIVersions.Has` so the chart degrades gracefully when the CRD is absent.

## RBAC

- Create Role/RoleBinding (or ClusterRole/Binding) scoped to least privilege, toggled by `rbac.create`.
- Bind to the chart's own ServiceAccount, not `default`.
- Make `clusterRole` vs namespaced `role` a deliberate choice; prefer namespaced.

## Dependencies

- Pin dependency versions in `Chart.yaml` and commit `Chart.lock`.
- Gate optional subcharts with `condition:` so users can disable them.
- Use `global` values for cross-cutting config (image registry, image pull secrets) shared parent↔subchart.

## Templating discipline

- **Namespace all `define` names** (`mychart.x`) — names are global.
- **`include … | nindent N`**, never bare `template`, for anything indented.
- Guard optional value access with `with`/`default`/`hasKey` to avoid `nil pointer` errors.
- Keep manifests one-resource-per-file, named after the kind (`deployment.yaml`, `service.yaml`).
- Put reusable logic in `_helpers.tpl`; consider a **library chart** when many app charts share templating.

## Pre-ship checklist

- [ ] `helm lint --strict` clean
- [ ] `helm template` with realistic values renders valid YAML; `kubeconform` passes
- [ ] `values.schema.json` present and enforcing required/typed inputs
- [ ] Resource requests/limits, probes, and securityContext set and configurable
- [ ] Image tag not `latest`; defaults to `appVersion`
- [ ] Labels/selectorLabels split correctly; recommended labels applied
- [ ] `Chart.yaml` `version` bumped; dependencies pinned; `Chart.lock` committed
- [ ] Secrets required, never defaulted to real values
