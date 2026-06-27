#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 <<'PY'
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

repo_root = Path(".").resolve()

tracked_files = subprocess.run(
    ["git", "ls-files"],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()

markdown_files = sorted(path for path in tracked_files if path.endswith(".md"))

if not markdown_files:
    print("No tracked Markdown files found.")
    sys.exit(0)

inline_link_re = re.compile(r"(?<!\!)\[[^\]]+\]\(([^)]+)\)")
ref_def_re = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(.+)$")
external_re = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")


def normalize_target(raw: str) -> str:
    target = raw.strip()
    if not target:
        return ""
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    else:
        target = target.split(maxsplit=1)[0]
    return target.strip()


def resolve_target(source: Path, target: str) -> Path | None:
    if not target or target.startswith("#") or external_re.match(target):
        return None

    cleaned = target.replace(r"\(", "(").replace(r"\)", ")")
    path_part = cleaned.split("#", 1)[0].split("?", 1)[0]

    if not path_part:
        return None

    decoded = unquote(path_part)
    if decoded.startswith("/"):
        return (repo_root / decoded.lstrip("/")).resolve()
    return (source.parent / decoded).resolve()


errors = []

for rel_path in markdown_files:
    path = repo_root / rel_path
    in_code_fence = False

    with path.open("r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            stripped = line.strip()
            if stripped.startswith("```"):
                in_code_fence = not in_code_fence
                continue
            if in_code_fence:
                continue

            targets = [m.group(1) for m in inline_link_re.finditer(line)]
            ref_match = ref_def_re.match(line)
            if ref_match:
                targets.append(ref_match.group(1))

            for raw_target in targets:
                target = normalize_target(raw_target)
                resolved = resolve_target(path, target)
                if resolved is None:
                    continue
                if not resolved.exists():
                    errors.append((rel_path, line_number, target))

if errors:
    for rel_path, line_number, target in errors:
        print(
            f"::error file={rel_path},line={line_number}::Broken internal link target '{target}'"
        )
    sys.exit(1)

print(f"Markdown internal link validation passed for {len(markdown_files)} file(s).")
PY
