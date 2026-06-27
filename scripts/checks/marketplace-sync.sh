#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 <<'PY'
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

errors = []
marketplace_path = Path(".claude-plugin/marketplace.json")

if not marketplace_path.exists():
    print("::error file=.claude-plugin/marketplace.json::Missing marketplace.json")
    sys.exit(1)

try:
    with marketplace_path.open("r", encoding="utf-8") as f:
        marketplace = json.load(f)
except Exception as exc:
    print(f"::error file=.claude-plugin/marketplace.json::Invalid JSON: {exc}")
    sys.exit(1)

entries = marketplace.get("plugins")
if not isinstance(entries, list):
    print("::error file=.claude-plugin/marketplace.json::'plugins' must be an array")
    sys.exit(1)

entry_names = []

for index, entry in enumerate(entries):
    location = f".claude-plugin/marketplace.json (plugins[{index}])"
    if not isinstance(entry, dict):
        errors.append(f"{location} must be an object")
        continue

    name = entry.get("name")
    source = entry.get("source")

    if not isinstance(name, str) or not name.strip():
        errors.append(f"{location} is missing a non-empty 'name'")
        continue

    if not isinstance(source, str) or not source.strip():
        errors.append(f"{location} is missing a non-empty 'source'")
        continue

    expected_source = f"./plugins/{name}"
    if source != expected_source:
        errors.append(
            f"{location} has source '{source}', expected '{expected_source}' for standard layout"
        )

    source_path = Path(source[2:] if source.startswith("./") else source)
    manifest_path = source_path / ".claude-plugin" / "plugin.json"

    if not manifest_path.exists():
        errors.append(f"{location} points to missing manifest: {manifest_path.as_posix()}")
    else:
        try:
            with manifest_path.open("r", encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception as exc:
            errors.append(f"{manifest_path.as_posix()} is invalid JSON: {exc}")
        else:
            manifest_name = manifest.get("name")
            if manifest_name != name:
                errors.append(
                    f"{manifest_path.as_posix()} has name '{manifest_name}', expected '{name}'"
                )

    entry_names.append(name)

duplicates = sorted(name for name, count in Counter(entry_names).items() if count > 1)
for dup in duplicates:
    errors.append(f"Marketplace contains duplicate plugin entry '{dup}'")

tracked_files = subprocess.run(
    ["git", "ls-files"],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()

tracked_plugin_dirs = sorted(
    {
        parts[1]
        for path in tracked_files
        if (parts := path.split("/")) and len(parts) >= 3 and parts[0] == "plugins"
    }
)

entry_set = set(entry_names)
tracked_set = set(tracked_plugin_dirs)

extra_dirs = sorted(tracked_set - entry_set)
missing_dirs = sorted(entry_set - tracked_set)

if extra_dirs:
    errors.append(
        "Tracked plugin directories missing from marketplace entries: "
        + ", ".join(extra_dirs)
    )

if missing_dirs:
    errors.append(
        "Marketplace entries missing tracked plugin directories: "
        + ", ".join(missing_dirs)
    )

if errors:
    for message in errors:
        print(f"::error::{message}")
    sys.exit(1)

print(f"Marketplace consistency passed for {len(entry_names)} plugin(s).")
PY
