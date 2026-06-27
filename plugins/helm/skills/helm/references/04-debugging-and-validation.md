# Debugging and validation

First classify the failure: **render-time** (chart won't produce valid YAML — no cluster needed) or **runtime** (release misbehaves — needs live evidence). Mixing them up wastes time.

## Render-time: the local debugging ladder

Work from cheapest/most-local to most-involved:

```bash
helm lint ./mychart --strict          # 1. static analysis; --strict fails on warnings too
helm template rel ./mychart           # 2. render everything; read the actual YAML
helm template rel ./mychart -f prod.yaml --set image.tag=1.2.3   # 3. render with real values
helm template rel ./mychart -s templates/deployment.yaml         # 4. render ONE file to isolate
helm install rel ./mychart --dry-run=server --debug              # 5. render + validate against the live API
```

- **`--debug`** prints the computed values and the full rendered manifest, even alongside errors — your highest-signal tool.
- **`--dry-run=server`** (Helm 3.13+) runs `lookup` functions and validates resources against the real API server (catches bad apiVersions, schema violations); plain `--dry-run` (client) skips that.
- **`-s/--show-only templates/x.yaml`** narrows rendering to one template so a single broken file isn't buried.

**When a YAML parse error blocks all output**, comment out the suspect block with `#` and re-run `helm template --debug` — everything else renders so you can localize the fault, then re-enable and fix.

## Common render-time errors

| Symptom | Cause and fix |
|---------|---------------|
| `nil pointer evaluating interface {}.X` | Accessing a sub-key of an unset value. Guard with `{{- with .Values.a }}…{{- end }}`, `default`, or `hasKey`. |
| `did not find expected key` / `mapping values are not allowed` | Indentation wrong in output — almost always a missing `nindent`, or `template` used where `include \| nindent` was needed. |
| `wrong type for value` | A number was quoted or a string left unquoted; fix `quote`/`toString`. |
| `error calling include: template: no template "X"` | Helper name typo or not namespaced/defined; check `_helpers.tpl`. |
| `unclosed action` / `unexpected "}" in operand` | Missing/extra `{{ end }}` or malformed action. |
| `execution error … required` | A `required` function fired — supply the value. |
| Output has stray blank lines | Whitespace control — use `{{-`/`-}}` and `nindent`. |

## Validate rendered manifests against the Kubernetes schema

`helm lint` checks chart conventions, not whether the output is valid Kubernetes. Render, then validate the manifests:

```bash
helm template rel ./mychart -f prod.yaml > /tmp/rendered.yaml
kubeconform -summary -strict /tmp/rendered.yaml      # validate against k8s + CRD schemas
yamllint /tmp/rendered.yaml                          # catch YAML lint issues
```

`kubeconform` (successor to `kubeval`) checks resources against the Kubernetes OpenAPI schema and can load CRD schemas; it's the right pre-deploy gate. The bundled `scripts/helm-chart-validate.sh` chains lint → template → yamllint/kubeconform when those tools are present.

## Runtime: debugging a release

```bash
helm status my-release -n my-ns                 # status + NOTES
helm history my-release -n my-ns                # revisions and their states
helm get manifest my-release -n my-ns           # what Helm actually applied (source of truth)
helm get values my-release -n my-ns -a          # computed values in effect
kubectl get events -n my-ns --sort-by=.lastTimestamp
kubectl describe deploy/<name> -n my-ns
kubectl logs deploy/<name> -n my-ns --all-containers --tail=100
```

Separate **release health** from **workload health**: `helm status` can say `deployed` while pods are `CrashLoopBackOff`. If the release deployed but the app is broken, pivot to `kubectl` on the rendered objects. `bash scripts/helm-release-debug.sh my-release -n my-ns` collects this in one pass.

### "My values aren't taking effect"

1. `helm get values my-release -n my-ns -a` — confirm what Helm actually computed.
2. Check precedence: `--set` overrides `-f`; later `-f` overrides earlier; `--set` *replaces* arrays.
3. On upgrade, confirm `--reuse-values` vs `--reset-values` semantics (see `03-cli-and-release-lifecycle.md`).
4. Confirm the template actually *reads* the value (`helm template` and grep the output).

## Recovering a stuck release

A release stuck in `pending-install`, `pending-upgrade`, or `uninstalling` usually means a previous Helm operation was interrupted (process killed, timeout, cluster blip) and never recorded a terminal state.

```bash
helm history my-release -n my-ns        # confirm the stuck/pending revision
```

Options, least-destructive first:

- **`helm rollback my-release <last-good-revision> -n my-ns`** — return to a known-good revision. Often clears a `pending-upgrade`.
- **`helm upgrade ... --atomic`** going forward so future failures self-recover.
- If rollback won't proceed, the release Secret may be wedged. The Helm 3 release state lives in Secrets named `sh.helm.release.v1.<release>.v<rev>`:
  ```bash
  kubectl get secret -n my-ns -l owner=helm,name=my-release
  ```
  Deleting the *latest* pending revision Secret can unstick Helm, but **this is destructive metadata surgery** — confirm with the user, back up the Secret first, and prefer `rollback`. The `helm-mapkubeapis` plugin and `helm rollback` cover most cases without manual surgery.

## helm test for post-deploy validation

```bash
helm test my-release -n my-ns
```

Runs the chart's `templates/tests/` hook Pods against the live release. A good smoke-test gate after install/upgrade in CI.
