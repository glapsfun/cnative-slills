#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mapfile -t shell_files < <(git ls-files | grep -E '\.sh$' || true)

if [[ ${#shell_files[@]} -eq 0 ]]; then
  echo "No tracked shell scripts found."
  exit 0
fi

errors=0

for file in "${shell_files[@]}"; do
  if ! bash -n "$file"; then
    echo "::error file=$file::Shell syntax validation failed"
    errors=$((errors + 1))
  fi
done

if (( errors > 0 )); then
  echo "Shell syntax validation failed with $errors issue(s)."
  exit 1
fi

echo "Shell syntax validation passed for ${#shell_files[@]} file(s)."
