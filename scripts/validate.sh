#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FAST_CHECKS=(structure marketplace-sync json yaml shell-syntax)
SLOW_CHECKS=(markdown-links)

usage() {
  cat <<'EOF'
Usage: scripts/validate.sh [--fast|--slow|--all]

Run repository validation checks from scripts/checks/.
  --fast      Structure, marketplace sync, JSON, YAML, shell syntax (default).
  --slow      Markdown internal links.
  --all       Fast and slow checks.
  -h, --help  Show this help.
EOF
}

mode="fast"
case "${1:-}" in
  --fast | "") mode="fast" ;;
  --slow) mode="slow" ;;
  --all) mode="all" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

case "$mode" in
  fast) checks=("${FAST_CHECKS[@]}") ;;
  slow) checks=("${SLOW_CHECKS[@]}") ;;
  all) checks=("${FAST_CHECKS[@]}" "${SLOW_CHECKS[@]}") ;;
esac

failed=0
for check in "${checks[@]}"; do
  log_info "validate: $check"
  if ! bash "$SCRIPT_DIR/checks/$check.sh"; then
    failed=$((failed + 1))
  fi
done

if ((failed > 0)); then
  log_error "$failed validation check(s) failed"
  exit 1
fi

log_ok "validation passed ($mode)"
