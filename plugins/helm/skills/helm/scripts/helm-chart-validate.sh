#!/usr/bin/env bash
#
# helm-chart-validate.sh — read-only quality gate for a Helm chart.
#
# Chains the checks every chart should pass before it ships:
#   1. helm lint --strict   chart conventions + syntax (fails on warnings)
#   2. helm template         renders the chart to valid YAML with the given values
#   3. yamllint              YAML hygiene on the rendered output (if installed)
#   4. kubeconform           Kubernetes schema validation (if installed)
#
# Missing optional tools (yamllint, kubeconform) are reported and skipped, not
# failed. Exits non-zero if any run check fails. Makes no changes and touches
# no cluster (rendering is client-side).

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
RENDERED=""

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] <chart-dir>

Validate a Helm chart: lint --strict, template, then yamllint + kubeconform
on the rendered manifests when those tools are available.

Options:
  -f, --values FILE   Values file to render with (repeatable)
  --set KEY=VALUE     Override a value (repeatable, passed to helm template)
  -h, --help          Show this help and exit

Exit status: 0 if all run checks pass, 1 otherwise.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 2
}

cleanup() {
  local rc=$?
  [[ -n "${RENDERED}" && -f "${RENDERED}" ]] && rm -f "${RENDERED}"
  trap - EXIT
  exit "${rc}"
}
trap cleanup EXIT

main() {
  local chart=""
  local -a helm_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f | --values)
        [[ $# -ge 2 ]] || die "$1 needs a file argument"
        helm_args+=("--values" "$2")
        shift 2
        ;;
      --set)
        [[ $# -ge 2 ]] || die "--set needs a KEY=VALUE argument"
        helm_args+=("--set" "$2")
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*) die "unknown option: $1" ;;
      *)
        [[ -z "${chart}" ]] || die "only one chart directory may be given"
        chart="$1"
        shift
        ;;
    esac
  done

  [[ -n "${chart}" ]] || {
    usage >&2
    die "no chart directory given"
  }
  [[ -d "${chart}" ]] || die "not a directory: ${chart}"
  [[ -f "${chart}/Chart.yaml" ]] || die "no Chart.yaml in ${chart} — is this a chart?"
  command -v helm >/dev/null 2>&1 || die "helm not found (https://helm.sh/docs/intro/install/)"

  local failures=0

  log "==> helm lint --strict ${chart}"
  if helm lint --strict "${chart}" "${helm_args[@]}"; then
    log "  [ok]   helm lint"
  else
    log "  [FAIL] helm lint"
    ((failures++)) || true
  fi

  log "==> helm template ${chart}"
  RENDERED="$(mktemp "${TMPDIR:-/tmp}/helm-rendered.XXXXXX.yaml")"
  if helm template "release-check" "${chart}" "${helm_args[@]}" >"${RENDERED}" 2>/tmp/helm-template-err.$$; then
    log "  [ok]   helm template (rendered $(grep -c '^kind:' "${RENDERED}" 2>/dev/null || echo '?') resources)"
  else
    log "  [FAIL] helm template:"
    sed 's/^/        /' /tmp/helm-template-err.$$ >&2 2>/dev/null || true
    rm -f /tmp/helm-template-err.$$ 2>/dev/null || true
    ((failures++)) || true
    log ""
    log "${failures} check(s) failed — fix rendering before the remaining checks are meaningful."
    return 1
  fi
  rm -f /tmp/helm-template-err.$$ 2>/dev/null || true

  if command -v yamllint >/dev/null 2>&1; then
    log "==> yamllint (rendered)"
    if yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "${RENDERED}"; then
      log "  [ok]   yamllint"
    else
      log "  [warn] yamllint reported issues (see above)"
    fi
  else
    log "note: yamllint not installed — skipping (pip install yamllint)"
  fi

  if command -v kubeconform >/dev/null 2>&1; then
    log "==> kubeconform (rendered)"
    if kubeconform -summary -strict -ignore-missing-schemas "${RENDERED}"; then
      log "  [ok]   kubeconform"
    else
      log "  [FAIL] kubeconform"
      ((failures++)) || true
    fi
  else
    log "note: kubeconform not installed — skipping (brew install kubeconform)"
  fi

  log ""
  if ((failures == 0)); then
    log "All run checks passed for ${chart}."
    return 0
  fi
  log "${failures} check(s) failed for ${chart}."
  return 1
}

main "$@"
