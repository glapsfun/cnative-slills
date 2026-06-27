# Templating: Go text/template + Sprig

Helm templates are [Go `text/template`](https://pkg.go.dev/text/template) plus the [Sprig](https://masterminds.github.io/sprig/) function library and a handful of Helm-specific additions. Output is YAML, where **indentation is structure** — most template bugs are really whitespace bugs.

## Built-in objects

Top-level objects available in every template (note the capitalization — built-ins are PascalCase):

| Object | What it holds |
|--------|---------------|
| `.Release.Name` / `.Release.Namespace` | Release name and target namespace |
| `.Release.IsInstall` / `.Release.IsUpgrade` | Booleans for the current action |
| `.Release.Revision` | Revision number (1 on install) |
| `.Chart.Name` / `.Chart.Version` / `.Chart.AppVersion` | From `Chart.yaml` |
| `.Values` | The merged values (defaults + `-f` + `--set`) |
| `.Files` | Access to non-template files in the chart (`.Files.Get`, `.Files.Glob`, `.Files.AsConfig`, `.Files.AsSecrets`) |
| `.Capabilities` | Cluster capabilities (`.APIVersions.Has "batch/v1"`, `.KubeVersion`) |
| `.Template.Name` / `.Template.BasePath` | The current template's path |

## Pipelines and functions

A pipeline chains functions with `|`, feeding the previous result as the **last** argument:

```yaml
drink: {{ .Values.favorite.drink | default "tea" | quote }}
food:  {{ .Values.favorite.food | upper | quote }}
```

High-value functions you'll use constantly:

| Function | Purpose |
|----------|---------|
| `quote` / `squote` | Wrap in double/single quotes (prevents YAML type coercion) |
| `default VALUE` | Fallback when the piped value is empty |
| `required "msg" .Values.x` | Fail rendering with a message if the value is empty — enforce mandatory inputs |
| `toYaml` | Serialize a value subtree to YAML (for `resources`, `nodeSelector`, etc.) |
| `indent N` / `nindent N` | Indent every line N spaces; `nindent` also prepends a newline |
| `trim` / `trimSuffix` / `trunc` | String trimming; `trunc 63` for label/DNS length limits |
| `printf` | Compose strings (helper names, fullnames) |
| `tpl` | Render a string *value* as a template (e.g. values containing `{{ }}`) |
| `lookup` | Read a live cluster object (only with `--dry-run=server`/real install) |
| `b64enc` / `b64dec` | Base64 for Secret data |
| `sha256sum` | Checksum (classic trick: roll pods on ConfigMap change) |

Operators are functions: `eq`, `ne`, `lt`, `gt`, `and`, `or`, `not`, grouped with parentheses: `{{ if and (.Values.a) (eq .Values.b "x") }}`.

## Named templates: define / include / template

Named templates (partials) live in `_helpers.tpl` (underscore-prefixed files aren't rendered as manifests). **Namespace every name** with the chart name — names are global and collide across subcharts.

```yaml
{{/* in _helpers.tpl */}}
{{- define "mychart.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
```

```yaml
{{/* in a manifest */}}
metadata:
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
```

**Always prefer `include` over `template`.** `include` returns a string you can pipe into `nindent`/`indent` to fix indentation; the `template` action emits directly and **cannot be piped**, so you can't correct its indentation. This single distinction prevents most "labels misaligned" bugs.

**Pass scope explicitly with the trailing `.`** — `include "mychart.labels" .`. Without it, the template gets no context and `.Values`/`.Release` are undefined inside it.

## Flow control: if / with / range

```yaml
{{- if .Values.ingress.enabled }}
# ...ingress manifest...
{{- end }}

{{- with .Values.nodeSelector }}      # rebinds . to nodeSelector inside the block
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}

{{- range .Values.env }}              # iterate a list
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

{{- range $key, $val := .Values.labels }}   # iterate a map
{{ $key }}: {{ $val | quote }}
{{- end }}
```

**Scope gotcha:** inside `with` and `range`, `.` is rebound to the current item, so `.Release`/`.Values` are no longer reachable as `.`. Capture the root with **`$`** (always the top context) to reach them: `{{ range .Values.items }}{{ $.Release.Name }}-{{ .name }}{{ end }}`.

## Variables

```yaml
{{- $fullName := include "mychart.fullname" . -}}
{{- $svcPort := .Values.service.port -}}
name: {{ $fullName }}
```

Variables (`$name`) keep their value across scope changes, which is the clean way to use a root-context value inside a `range`/`with`.

## Whitespace control

`{{-` trims preceding whitespace (including the newline); `-}}` trims following whitespace. Because YAML cares about indentation and blank lines, control it deliberately:

```yaml
# `{{- ... }}` on the action line removes the leading newline/indent that the action would otherwise leave:
spec:
  replicas: {{ .Values.replicaCount }}
  {{- if .Values.extra }}
  extra: {{ .Values.extra }}
  {{- end }}
```

Use `nindent` (not manual spaces) when injecting multi-line blocks so indentation is computed, not hand-counted. When debugging stray blank lines, `helm template` and look at the literal output.

## Common template errors and their causes

| Error | Cause / fix |
|-------|-------------|
| `nil pointer evaluating interface {}.foo` | Accessing `.Values.a.b` where `a` is unset. Guard with `if`, `with`, or `default dict`: `{{- with .Values.a }}{{ .b }}{{- end }}`. |
| `wrong type for value; expected ... got string` | A number got quoted (or vice versa). Check `quote`/`toString` usage. |
| `did not find expected key` / YAML parse error | Indentation off — usually a missing `nindent` or a `template` used where `include | nindent` was needed. Render and read the YAML. |
| `error converting YAML to JSON` | Tabs in output, or a value with special chars not quoted. |
| `function "X" not defined` | Sprig version too old, or a typo. Check `helm version`. |
| `unclosed action` / `unexpected EOF` | Missing `{{ end }}` for an `if`/`with`/`range`/`define`. |

When a YAML parse error hides the rendered output, temporarily comment out the offending block with `#` and re-run `helm template --debug` to see everything else render — then narrow in.
