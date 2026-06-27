#!/usr/bin/env bash
#
# helm-doc-discover.sh — print authoritative Helm documentation links.
#
# Use when refreshing this skill or when you need a canonical reference for a
# behavior that may be version-sensitive. Prefer these primary sources over
# memory for exact CLI flags, template function behavior, and best practices.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help]

Print curated, authoritative documentation links for Helm, its CLI, the chart
template guide, Go text/template, Sprig, and Artifact Hub. Read-only.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cat <<'DOCS'
## Helm core
- Docs home:                     https://helm.sh/docs/
- CLI command reference:         https://helm.sh/docs/helm/
- Topics (architecture, etc.):   https://helm.sh/docs/topics/
- Source / releases:             https://github.com/helm/helm

## Chart authoring
- Charts guide:                  https://helm.sh/docs/topics/charts/
- Chart.yaml & structure:        https://helm.sh/docs/topics/charts/#the-chart-file-structure
- Chart best practices:          https://helm.sh/docs/chart_best_practices/
- Values best practices:         https://helm.sh/docs/chart_best_practices/values/
- Template best practices:       https://helm.sh/docs/chart_best_practices/templates/
- Labels & annotations:          https://helm.sh/docs/chart_best_practices/labels/
- CRDs:                          https://helm.sh/docs/chart_best_practices/custom_resource_definitions/

## Templating
- Chart template guide:          https://helm.sh/docs/chart_template_guide/
- Built-in objects:              https://helm.sh/docs/chart_template_guide/builtin_objects/
- Functions & pipelines:         https://helm.sh/docs/chart_template_guide/functions_and_pipelines/
- Flow control:                  https://helm.sh/docs/chart_template_guide/control_structures/
- Named templates:               https://helm.sh/docs/chart_template_guide/named_templates/
- Variables:                     https://helm.sh/docs/chart_template_guide/variables/
- Debugging templates:           https://helm.sh/docs/chart_template_guide/debugging/
- Go text/template (stdlib):     https://pkg.go.dev/text/template
- Sprig function library:        https://masterminds.github.io/sprig/

## Release lifecycle & hooks
- Chart hooks:                   https://helm.sh/docs/topics/charts_hooks/
- Chart tests:                   https://helm.sh/docs/topics/chart_tests/

## Discovery & distribution
- Artifact Hub:                  https://artifacthub.io
- OCI registries:                https://helm.sh/docs/topics/registries/
- helm-diff plugin:              https://github.com/databus23/helm-diff

## Validation tooling
- kubeconform:                   https://github.com/yannh/kubeconform
DOCS
