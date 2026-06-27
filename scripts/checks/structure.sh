#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

errors=0

if [[ ! -f ".claude-plugin/marketplace.json" ]]; then
  echo "::error file=.claude-plugin/marketplace.json::Missing marketplace.json at repository root"
  exit 1
fi

mapfile -t plugins < <(git ls-files | awk -F/ 'NF >= 3 && $1 == "plugins" {print $2}' | sort -u)

if [[ ${#plugins[@]} -eq 0 ]]; then
  echo "::error::No tracked plugin directories found under plugins/"
  exit 1
fi

for plugin in "${plugins[@]}"; do
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  skill_root="plugins/$plugin/skills/$plugin"
  skill_file="$skill_root/SKILL.md"
  refs_dir="$skill_root/references"

  for required in "$manifest" "$skill_file"; do
    if ! git ls-files --error-unmatch "$required" >/dev/null 2>&1; then
      echo "::error file=$required::Plugin '$plugin' is missing required file: $required"
      errors=$((errors + 1))
    fi
  done

  if git ls-files -- "$skill_root/evals" | grep -q .; then
    evals_file="$skill_root/evals/evals.json"
    if ! git ls-files --error-unmatch "$evals_file" >/dev/null 2>&1; then
      echo "::error file=$evals_file::Plugin '$plugin' has eval files but is missing $evals_file"
      errors=$((errors + 1))
    fi
  fi

  if ! git ls-files -- "$refs_dir" | grep -Eq '\.md$'; then
    echo "::error file=$refs_dir::Plugin '$plugin' must include at least one markdown file under $refs_dir"
    errors=$((errors + 1))
  fi

  if git ls-files --error-unmatch "$manifest" >/dev/null 2>&1; then
    manifest_name="$(
      python3 - "$manifest" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
name = data.get("name")
print("" if name is None else str(name))
PY
    )"

    if [[ -z "$manifest_name" ]]; then
      echo "::error file=$manifest::Plugin manifest is missing a non-empty 'name' field"
      errors=$((errors + 1))
    elif [[ "$manifest_name" != "$plugin" ]]; then
      echo "::error file=$manifest::Plugin manifest name '$manifest_name' does not match directory name '$plugin'"
      errors=$((errors + 1))
    fi
  fi
done

if (( errors > 0 )); then
  echo "Structure validation failed with $errors issue(s)."
  exit 1
fi

echo "Structure validation passed for ${#plugins[@]} plugin(s)."
