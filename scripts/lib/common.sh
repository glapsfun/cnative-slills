#!/usr/bin/env bash
# Shared helpers for cnative-skills developer scripts.
# Source this file from other scripts; do not execute it directly.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
export REPO_ROOT

log_info() { printf '\033[0;34m[info]\033[0m  %s\n' "$*" >&2; }
log_warn() { printf '\033[0;33m[warn]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; }
log_ok() { printf '\033[0;32m[ok]\033[0m    %s\n' "$*" >&2; }

# have_tool NAME -> 0 if NAME is on PATH.
have_tool() { command -v "$1" >/dev/null 2>&1; }

# require_tool NAME [HINT] -> exit 1 if NAME is missing.
require_tool() {
  if ! have_tool "$1"; then
    log_error "required tool '$1' not found. ${2:-Install it and retry.}"
    exit 1
  fi
}

# skip_unless_tool NAME -> 0 if present. If missing: fatal in CI, else warn+return 1.
skip_unless_tool() {
  if have_tool "$1"; then
    return 0
  fi
  if [[ "${CI:-}" == "true" ]]; then
    log_error "tool '$1' missing in CI; scripts/bootstrap.sh --ci should have installed it"
    exit 1
  fi
  log_warn "tool '$1' not found; skipping its checks. Run scripts/bootstrap.sh to install."
  return 1
}
