#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 <<'PY'
import json
import subprocess
import sys

tracked_files = subprocess.run(
    ["git", "ls-files"],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()

json_files = sorted(path for path in tracked_files if path.endswith(".json"))

if not json_files:
    print("No tracked JSON files found.")
    sys.exit(0)

errors = []

for path in json_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            json.load(f)
    except Exception as exc:
        errors.append((path, str(exc)))

if errors:
    for path, error in errors:
        print(f"::error file={path}::Invalid JSON: {error}")
    sys.exit(1)

print(f"JSON validation passed for {len(json_files)} file(s).")
PY
