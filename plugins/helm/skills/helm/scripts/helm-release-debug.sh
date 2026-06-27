#!/usr/bin/env bash
#
# helm-release-debug.sh — collect diagnostics for an installed Helm release.
#
# Read-only. Gathers release status, revision history, the applied manifest,
# the computed values, hooks, and recent namespace events in one pass — the
# evidence you need before theorizing about a runtime failure. Makes no
# changes to the release or the cluster.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] <release-name>

Collect read-only diagnostics for a Helm release.

Options:
  -n, --namespace NS   Namespace of the release (default: current context ns)
  -h, --help           Show this help and exit
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 2
}

section() { printf '\n===== %s =====\n' "$1"; }

main() {
  local release=""
  local namespace=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --namespace)
        [[ $# -ge 2 ]] || die "$1 needs a namespace argument"
        namespace="$2"
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
        [[ -z "${release}" ]] || die "only one release name may be given"
        release="$1"
        shift
        ;;
    esac
  done

  [[ -n "${release}" ]] || {
    usage >&2
    die "no release name given"
  }
  command -v helm >/dev/null 2>&1 || die "helm not found"

  local -a ns=()
  [[ -n "${namespace}" ]] && ns=(--namespace "${namespace}")

  section "helm status"
  helm status "${release}" "${ns[@]}" 2>&1 || log "(status unavailable — is the release name/namespace correct? try 'helm list -A')"

  section "helm history"
  helm history "${release}" "${ns[@]}" 2>&1 || log "(history unavailable)"

  section "computed values (helm get values -a)"
  helm get values "${release}" "${ns[@]}" -a 2>&1 || log "(values unavailable)"

  section "hooks (helm get hooks)"
  helm get hooks "${release}" "${ns[@]}" 2>&1 | head -60 || log "(hooks unavailable)"

  section "applied manifest — resource summary"
  if helm get manifest "${release}" "${ns[@]}" >/tmp/helm-manifest.$$ 2>/dev/null; then
    grep -E '^(kind|  name):' /tmp/helm-manifest.$$ 2>/dev/null | paste - - 2>/dev/null ||
      echo "(could not summarize; run 'helm get manifest ${release}' to see full output)"
    rm -f /tmp/helm-manifest.$$ 2>/dev/null || true
  else
    log "(manifest unavailable)"
  fi

  if command -v kubectl >/dev/null 2>&1; then
    section "recent events in namespace"
    kubectl get events "${ns[@]}" --sort-by=.lastTimestamp 2>&1 | tail -25 ||
      log "(events unavailable — cluster unreachable?)"
  else
    log ""
    log "note: kubectl not found — skipping cluster events. Install kubectl for workload-level diagnostics."
  fi

  log ""
  log "Next steps:"
  log "  - Separate release health from workload health: a 'deployed' release can still have crashing pods."
  log "  - For a stuck pending-install/pending-upgrade, consider: helm rollback ${release} <last-good-rev>"
  log "  - Inspect workloads: kubectl describe / kubectl logs on the resources listed above."
}

main "$@"
