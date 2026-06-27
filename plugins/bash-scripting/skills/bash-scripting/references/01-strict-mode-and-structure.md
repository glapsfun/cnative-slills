# Strict mode, script structure, and error handling

## Contents

- [Strict mode for standalone execution](#strict-mode-for-standalone-execution)
- [`set -e` is a safety net, not a strategy](#set--e-is-a-safety-net-not-a-strategy)
- [Recommended script skeleton](#recommended-script-skeleton)
- [Argument parsing: `getopts` vs a `case` loop](#argument-parsing-getopts-vs-a-case-loop)
- [Exit codes](#exit-codes)
- [Functions](#functions)

## Strict mode for standalone execution

Enable strict mode only when the file is executed directly:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -Eeuo pipefail
  initialize_runtime
  install_traps
  main "$@"
fi
```

| Flag | Long form | What it prevents |
|------|-----------|------------------|
| `-e` | `errexit` | Continuing after an unhandled command fails, leaving the script in a half-done state. |
| `-u` | `nounset` | Silently using an empty value for a misspelled or unset variable (e.g. `rm -rf "$PREFX/"`). |
| `-o pipefail` | — | A pipeline reporting success when an early stage failed (`curl … \| tar …` where `curl` 404s). |
| `-E` | `errtrace` | An installed `ERR` trap not being inherited by functions, command substitutions, or subshell environments. |

Keep top-level code safe to source: define functions, but do not change the caller's shell options, `IFS`, traps, or runtime globals. Put state setup in `initialize_runtime`, trap changes in `install_traps`, and call both from the direct-execution guard. Quote expansions instead of globally changing `IFS`; use a command-scoped `IFS=` only for operations such as `read`.

Use `ERR` traps for failure diagnostics and `EXIT` traps for resource cleanup. `-E` only controls `ERR` inheritance; it does not make an `EXIT` cleanup handler more reliable.

## `set -e` is a safety net, not a strategy

`errexit` is genuinely useful but has surprising holes. Knowing them prevents both false confidence and confusing bugs:

- **It does not fire in a condition context.** Commands in `if`, `while`, `until`, `&&`, `||`, or negated with `!` are allowed to fail. `if grep -q foo file; then` won't exit on no-match — that's the point.
- **It does not fire for the left side of a pipe** (that's what `pipefail` is for).
- **Non-POSIX Bash clears `errexit` in command substitutions by default**, including current Bash releases. Bash 4.4+ can enable `shopt -s inherit_errexit`; guard that call with a version check because Bash 3.2 rejects the option. POSIX mode also preserves inheritance but changes other semantics. For Bash 3.2 and cross-version scripts, handle command-substitution failures explicitly (`if ! output=$(cmd); then …`) instead of relying on inherited `errexit`.
- **A function called in a condition disables `errexit` for its whole body.** `if my_func; then …` runs `my_func` with errexit effectively off. This surprises people constantly.
- **`local x=$(cmd)` masks the exit code** because `local` succeeds even if `cmd` fails. Split into `local x; x=$(cmd)` when you need to catch the failure.

Because of these, handle expected failures explicitly rather than relying solely on `-e`:

```bash
if ! output=$(some_command 2>&1); then
  log_error "some_command failed: ${output}"
  return 1
fi
```

## Recommended script skeleton

`scripts/bash-scaffold.sh` generates this; here is the shape and the reasoning:

```bash
#!/usr/bin/env bash

initialize_runtime() {
  # Resolve own location so the script works regardless of CWD.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  readonly SCRIPT_DIR
  SCRIPT_NAME="${0##*/}"
  readonly SCRIPT_NAME
  DRY_RUN=0
}

usage() {
  local script_name="${SCRIPT_NAME:-${0##*/}}"

  cat <<EOF
Usage: ${script_name} [OPTIONS] <arg>

Options:
  -v, --verbose   Enable verbose logging
  -n, --dry-run   Show actions without executing them
  -h, --help      Show this help and exit
EOF
}

# Logging to stderr keeps stdout reserved for real output.
# printf %q is Bash-only and produces reusable shell-escaped diagnostics.
log() {
  local level=$1
  shift
  printf '%s [%q]' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "${level}" >&2
  (($# == 0)) || printf ' %q' "$@" >&2
  printf '\n' >&2
}
log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
die()       { log_error "$@"; exit 1; }

cleanup_resources() {
  local failed=0

  # Check every action explicitly: errexit is disabled while this function runs under `if !`.
  # if ! rm -rf -- "${work_dir}"; then
  #   failed=1
  # fi

  return "${failed}"
}

cleanup() {
  local rc=$?
  trap - EXIT

  if ! cleanup_resources; then
    log_warn "cleanup failed" || :
  fi

  exit "${rc}"
}

install_traps() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

main() {
  local verbose=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose) verbose=1; shift ;;
      -n|--dry-run) dry_run=1; shift ;;
      -h|--help)    usage; exit 0 ;;
      --)           shift; break ;;
      -*)           die "unknown option: $1" ;;
      *)            break ;;
    esac
  done

  [[ $# -ge 1 ]] || { usage; die "missing required argument"; }

  # ... real work here ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -Eeuo pipefail
  initialize_runtime
  install_traps
  main "$@"
fi
```

`printf %q` is Bash-specific. Do not copy this formatter into a POSIX `sh` script.

Why each piece earns its place:

- **`SCRIPT_DIR` resolution** lets the script reference sibling files (`"${SCRIPT_DIR}/lib.sh"`) no matter where it's invoked from.
- **`readonly` constants** document intent and prevent accidental reassignment.
- **Logging functions to stderr** keep stdout parseable and give consistent, timestamped output.
- **Direct-execution initialization** enables strict mode, initializes runtime globals, installs traps, then calls `main`; sourcing only defines reusable functions.
- **`main "$@"` behind the source guard** means the file can be `source`d in a test to exercise individual functions without running `main` or changing caller state.

## Argument parsing: `getopts` vs a `case` loop

- **`getopts`** (POSIX, built in) handles short options (`-v`, `-o file`) cleanly and is the most portable choice, but it does **not** support long options (`--verbose`).
- **A manual `while`/`case` loop** (shown above) is the pragmatic choice when you want `--long` options. Always handle `--` to mark the end of options so user filenames starting with `-` are treated as data.

For complex CLIs, validate required arguments after parsing and emit `usage` on error. Never silently ignore unknown flags — fail fast.

## Exit codes

Use meaningful, documented exit codes. Convention: `0` success, `1` general error, `2` usage/argument error. Reserve higher codes for distinct failure classes a caller might branch on. Avoid colliding with reserved codes (126 not executable, 127 command not found, 128+N killed by signal N). Always `exit` with an explicit status from `main` rather than letting the script fall off the end with whatever the last command returned.

## Functions

- Declare function-local variables with `local` so they don't leak into global scope.
- Split declaration from assignment when capturing command output under `set -e`: `local out; out=$(cmd)`.
- Keep functions single-purpose; return status with `return N` and print results to stdout.
- Define functions as `name() { … }` — avoid the non-POSIX `function name { … }` keyword.
