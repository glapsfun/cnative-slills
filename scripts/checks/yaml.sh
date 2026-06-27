#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

cd "$REPO_ROOT"

mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')

if [[ ${#yaml_files[@]} -eq 0 ]]; then
  log_info "no tracked YAML files"
  exit 0
fi

skip_unless_tool yamllint || exit 0

yamllint -c .yamllint -- "${yaml_files[@]}"
log_ok "YAML lint passed for ${#yaml_files[@]} file(s)"
