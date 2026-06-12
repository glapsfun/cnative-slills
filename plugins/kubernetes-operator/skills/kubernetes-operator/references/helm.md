# Helm

## CLI essentials

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
helm search repo postgres; helm show values bitnami/postgresql > values.yaml
helm install <release> <chart> -n <ns> --create-namespace -f values.yaml
helm upgrade --install <release> <chart> -n <ns> -f values.yaml   # idempotent — the default verb for automation
helm list -A; helm status <release> -n <ns>
helm history <release> -n <ns>; helm rollback <release> [REVISION] -n <ns>
helm uninstall <release> -n <ns>
helm get values <release> -n <ns> [--all]    # what was actually deployed with
helm get manifest <release> -n <ns>          # rendered YAML of the live release
```

Values precedence (last wins): chart `values.yaml` → `-f a.yaml -f b.yaml` (in order) → `--set key=val`. Prefer `-f` files in git over `--set` (auditable, diffable). `--set` quirks: commas separate pairs, escape with `\,`; arrays as `key={a,b}` or `key[0]=a`.

## Chart anatomy

```
mychart/
├── Chart.yaml          # name, version (chart), appVersion (app), dependencies
├── values.yaml         # defaults — the chart's public API
├── charts/             # vendored dependency charts (via `helm dependency update`)
├── Chart.lock
└── templates/
    ├── _helpers.tpl    # named template definitions ({{ define "mychart.labels" }})
    ├── deployment.yaml
    ├── NOTES.txt       # printed after install
    └── tests/          # pods with helm.sh/hook: test → run via `helm test <release>`
```

Dependencies in `Chart.yaml` (`dependencies: [{name, version, repository, condition: postgresql.enabled}]`) → `helm dependency update`. Subchart values nest under the dependency's name in the parent's values.

## Templating

Go templates + Sprig. Key builtins: `.Values`, `.Release.Name|Namespace|Revision`, `.Chart.Name|Version|AppVersion`, `.Capabilities.KubeVersion|APIVersions`. Patterns that matter:

```yaml
{{ include "mychart.fullname" . }}                 # include (pipable) over template
{{- toYaml .Values.resources | nindent 12 }}       # embed maps with correct indentation
{{ .Values.host | required "host is required" }}
{{ .Values.tag | default .Chart.AppVersion }}
{{- if .Values.ingress.enabled }} ... {{- end }}
{{- range .Values.extraEnv }} ... {{- end }}
{{ .Values.password | quote }}                     # quote strings that could parse as numbers/bools
```

Checksums to roll pods on config change:
```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

## Hooks

Annotation `helm.sh/hook: pre-install|post-install|pre-upgrade|post-upgrade|pre-delete|post-delete|test` on a Job/Pod; order via `helm.sh/hook-weight`; cleanup via `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`. Hooks are not managed with the release — they don't get rolled back. Typical use: DB migrations as a `pre-upgrade` Job.

## Release internals & failure recovery

- Helm stores each revision as a Secret `sh.helm.release.v1.<release>.v<N>` in the release namespace; `--history-max` caps them (default 10).
- `--atomic` (rollback on failure) and `--wait --timeout 5m` (wait for readiness) make upgrades transactional. Without `--wait`, "deployed" only means manifests were accepted.
- **Stuck `pending-upgrade`/`pending-install`** (interrupted helm process): `helm rollback <release> <last-good>` — or delete the latest pending release Secret, then retry. Check with `helm history`.
- Helm uses three-way merge between old manifest, new manifest, and live state — out-of-band edits to helm-managed objects are usually overwritten on next upgrade.

## Debugging rendering

```bash
helm template <release> <chart> -f values.yaml          # render locally, no cluster
helm template ... --debug                                # show templates even when invalid
helm upgrade --install ... --dry-run=server              # render + server-side validation, nothing persisted
helm lint <chart>
helm diff upgrade <release> <chart> -f values.yaml       # helm-diff plugin: what would change
```

Workflow for "the chart is doing something weird": `helm get values` (what config is live) → `helm get manifest` (what YAML is live) → `helm template` with the same values (what the new version renders) → diff.

## OCI registries

```bash
helm package mychart/ && helm push mychart-0.1.0.tgz oci://registry.example.com/charts
helm install rel oci://registry.example.com/charts/mychart --version 0.1.0
```

## Helm under GitOps

Flux's `HelmRelease` (helm-controller) and Argo CD applications install charts *for* you — the desired chart version + values live in git. On such clusters, don't run `helm upgrade` by hand: the controller owns the release and will revert/conflict. Inspect with `helm list -A` (releases still visible) but change via the git repo. Flux tip: `flux get helmreleases -A` shows reconciliation state; a failed HelmRelease often surfaces the underlying helm error in `kubectl describe helmrelease`.
