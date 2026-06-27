#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHFMT_VERSION="v3.10.0"
ACTIONLINT_VERSION="v1.7.7"
GITLEAKS_VERSION="v8.21.2"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--ci]

Install developer tooling used by the scripts/ check suite:
  shellcheck shfmt yamllint actionlint prettier markdownlint-cli2
  gitleaks pre-commit (and git-cliff on macOS for local release dry-runs).

Options:
  --ci        Non-interactive install for Linux CI runners (apt/go/npm/pip).
  -h, --help  Show this help.

With no flag, installs via Homebrew on macOS.
EOF
}

bootstrap_macos() {
  require_tool brew "Install Homebrew from https://brew.sh"
  brew install \
    shellcheck shfmt yamllint actionlint \
    prettier markdownlint-cli2 gitleaks git-cliff pre-commit
}

bootstrap_ci() {
  require_tool go "Go must be available on the CI runner"
  require_tool npm "Node/npm must be available on the CI runner"
  require_tool python3 "Python 3 must be available on the CI runner"

  sudo apt-get update -y
  sudo apt-get install -y shellcheck

  go install "mvdan.cc/sh/v3/cmd/shfmt@${SHFMT_VERSION}"
  go install "github.com/rhysd/actionlint/cmd/actionlint@${ACTIONLINT_VERSION}"
  go install "github.com/gitleaks/gitleaks/v8@${GITLEAKS_VERSION}"

  python3 -m pip install --user --quiet yamllint pre-commit
  npm install -g --no-fund --no-audit prettier markdownlint-cli2

  # Persist tool locations to later workflow steps (git-cliff is provided by
  # the release workflow's action, so it is intentionally not installed here).
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$(go env GOPATH)/bin" >>"$GITHUB_PATH"
    echo "$HOME/.local/bin" >>"$GITHUB_PATH"
  fi
}

main() {
  case "${1:-}" in
    --ci) bootstrap_ci ;;
    -h | --help)
      usage
      exit 0
      ;;
    "")
      case "$(uname -s)" in
        Darwin) bootstrap_macos ;;
        *)
          log_error "Automated local install supports macOS only; use --ci or install tools manually."
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
  log_ok "bootstrap complete"
}

main "$@"
