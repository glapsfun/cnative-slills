#!/usr/bin/env bash
#
# helm-version-check.sh — report the Helm toolchain and target environment.
#
# Read-only. Detects the Helm client version, the active Kubernetes context and
# server version, installed Helm plugins (notably helm-diff), and whether the
# supporting validators (yamllint, kubeconform) are available — so version- and
# cluster-sensitive advice can be matched to reality instead of assumed.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help]

Reports helm version, Kubernetes context/version, installed helm plugins, and
availability of helm-diff, yamllint, and kubeconform. Read-only; no changes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

section() { printf '\n## %s\n' "$1"; }

tool_status() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    printf '  %-12s installed\n' "${name}"
  else
    printf '  %-12s MISSING\n' "${name}"
  fi
}

section "Helm client"
if command -v helm >/dev/null 2>&1; then
  helm version --short 2>/dev/null || helm version 2>/dev/null || echo "  helm present but 'helm version' failed"
else
  echo "  helm: not found (install: https://helm.sh/docs/intro/install/)"
fi

section "Kubernetes context"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "  kubectl: not found"
elif ! kubectl config current-context >/dev/null 2>&1; then
  echo "  kubectl context: unavailable (no kubeconfig context set)"
else
  echo "  context: $(kubectl config current-context)"
  if kubectl version -o json --request-timeout=5s >/dev/null 2>&1; then
    server_ver="$(kubectl version -o json --request-timeout=5s 2>/dev/null |
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("serverVersion",{}).get("gitVersion","unknown"))' 2>/dev/null || echo unknown)"
    echo "  server version: ${server_ver}"
  else
    echo "  server: unreachable (chart 'lookup' and --dry-run=server will not work)"
  fi
fi

section "Helm plugins"
if command -v helm >/dev/null 2>&1; then
  if helm plugin list 2>/dev/null | tail -n +2 | grep -q .; then
    helm plugin list 2>/dev/null | tail -n +2 | awk '{printf "  %s %s\n", $1, $2}'
    helm plugin list 2>/dev/null | grep -qi diff && echo "  (helm-diff present — you can preview upgrades with 'helm diff upgrade')"
  else
    echo "  no plugins installed (consider helm-diff: helm plugin install https://github.com/databus23/helm-diff)"
  fi
else
  echo "  skipped (helm not found)"
fi

section "Supporting validators"
tool_status yamllint
tool_status kubeconform
tool_status helm

section "Summary"
missing=()
command -v helm >/dev/null 2>&1 || missing+=("helm")
command -v kubeconform >/dev/null 2>&1 || missing+=("kubeconform")
if ((${#missing[@]} == 0)); then
  echo "  Core tooling present — you can lint, render, and schema-validate charts."
else
  printf '  Missing: %s\n' "$(
    IFS=' '
    echo "${missing[*]}"
  )"
  echo "  helm:        https://helm.sh/docs/intro/install/"
  echo "  kubeconform: https://github.com/yannh/kubeconform (brew install kubeconform)"
fi
