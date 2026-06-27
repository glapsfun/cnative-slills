#!/usr/bin/env bash
#
# bash-lint.sh — one-command quality gate for shell scripts.
#
# Chains the three checks every script should pass before it ships:
#   1. shell -n    syntax check with a shebang-aware parser (always available)
#   2. shellcheck  static analysis for correctness bugs (if installed)
#   3. shfmt -d    formatting diff (if installed)
#
# Missing optional tools are reported and skipped, not treated as failures,
# so the script is useful even on a bare machine. Exits non-zero if any
# available check fails, making it safe to wire into CI or a pre-commit hook.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

COLLECTION_TMPDIR=''
COLLECTION_FAILED_PATH=''
NORMALIZED_PATH=''

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] <file-or-dir> [more...]

Run a shell syntax parser, shellcheck, and shfmt against the given shell scripts.
Directories are searched recursively for *.sh, *.bash, and executable
extensionless files with a supported shell shebang.

Options:
  --no-shellcheck   Skip the shellcheck stage
  --no-shfmt        Skip the shfmt stage
  --fix             With shfmt available, rewrite files in place (shfmt -w)
  -h, --help        Show this help and exit

Exit status: 0 if all run checks pass, 1 otherwise.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 2
}

cleanup_collection_tmpdir() {
  if [[ -n ${COLLECTION_TMPDIR} ]]; then
    rm -rf -- "${COLLECTION_TMPDIR}"
  fi
}

normalize_path() {
  case "$1" in
    -*) NORMALIZED_PATH=./"$1" ;;
    *) NORMALIZED_PATH=$1 ;;
  esac
}

collect_scripts() {
  # Materialize a NUL-delimited list only after each directory traversal succeeds.
  local output_file=$1
  local find_output=$2
  local find_error=$3
  shift 3

  local file
  local path
  local search_path

  : >"${output_file}" || return 1
  for path in "$@"; do
    if [[ -d "${path}" ]]; then
      normalize_path "${path}"
      search_path=${NORMALIZED_PATH}
      if ! find "${search_path}" -type f -print0 >"${find_output}" 2>"${find_error}"; then
        COLLECTION_FAILED_PATH=${path}
        return 1
      fi

      while IFS= read -r -d '' file; do
        case "${file##*/}" in
          *.sh | *.bash)
            printf '%s\0' "${file}" >>"${output_file}" || return 1
            ;;
          *.*)
            ;;
          *)
            if [[ -x "${file}" ]] && decode_shebang "${file}" >/dev/null; then
              printf '%s\0' "${file}" >>"${output_file}" || return 1
            fi
            ;;
        esac
      done <"${find_output}"
    else
      normalize_path "${path}"
      printf '%s\0' "${NORMALIZED_PATH}" >>"${output_file}" || return 1
    fi
  done
}

decode_shebang() {
  local command_name=''
  local dialect=''
  local first_line=''
  local first_word=''
  local interpreter=''
  local interpreter_options=''
  local second_word=''

  IFS= read -r first_line <"$1" || :
  [[ ${first_line} == '#!'* ]] || return 1

  IFS=$' \t' read -r command_name first_word second_word interpreter_options <<<"${first_line#\#!}"
  : "${interpreter_options}" # Syntax checks select the interpreter but do not replay its options.
  dialect=${command_name##*/}
  if [[ ${dialect} == env ]]; then
    case "${first_word}" in
      -S) interpreter=${second_word} ;;
      -S?*) interpreter=${first_word#-S} ;;
      *) interpreter=${first_word} ;;
    esac
    dialect=${interpreter##*/}
  fi

  case "${dialect}" in
    bash | sh | dash) printf '%s\n' "${dialect}" ;;
    *) return 1 ;;
  esac
}

syntax_parser() {
  local dialect

  if ! dialect="$(decode_shebang "$1")"; then
    dialect=bash
  fi

  case "${dialect}" in
    sh)
      printf 'sh\n'
      ;;
    dash)
      if command -v dash >/dev/null 2>&1; then
        printf 'dash\n'
      else
        printf 'sh\n'
      fi
      ;;
    *)
      printf 'bash\n'
      ;;
  esac
}

main() {
  local run_shellcheck=1 run_shfmt=1 fix=0
  local -a paths=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-shellcheck)
        run_shellcheck=0
        shift
        ;;
      --no-shfmt)
        run_shfmt=0
        shift
        ;;
      --fix)
        fix=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          paths+=("$1")
          shift
        done
        ;;
      -*) die "unknown option: $1" ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  ((${#paths[@]} >= 1)) || {
    usage
    die "no files or directories given"
  }

  # Validate in this shell so errors are not hidden by process substitution.
  local path
  for path in "${paths[@]}"; do
    [[ -d "${path}" || -f "${path}" ]] || die "no such file or directory: ${path}"
  done

  # Tool availability.
  local have_shellcheck=0 have_shfmt=0
  command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1
  command -v shfmt >/dev/null 2>&1 && have_shfmt=1
  ((run_shellcheck && !have_shellcheck)) && log "note: shellcheck not installed — skipping (brew install shellcheck)"
  ((run_shfmt && !have_shfmt)) && log "note: shfmt not installed — skipping (brew install shfmt)"

  COLLECTION_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bash-lint.XXXXXX")" ||
    die "could not create temporary directory"
  trap cleanup_collection_tmpdir EXIT

  # Gather target scripts safely, consuming results only after find succeeds.
  local collection_file="${COLLECTION_TMPDIR}/scripts"
  local find_error="${COLLECTION_TMPDIR}/find-error"
  local find_output="${COLLECTION_TMPDIR}/find-output"
  if ! collect_scripts "${collection_file}" "${find_output}" "${find_error}" "${paths[@]}"; then
    if [[ -n ${COLLECTION_FAILED_PATH} ]]; then
      die "failed to search directory: ${COLLECTION_FAILED_PATH}"
    fi
    die "failed to collect shell files"
  fi

  local -a scripts=()
  local duplicate
  local existing
  while IFS= read -r -d '' f; do
    duplicate=0
    if ((${#scripts[@]} > 0)); then
      for existing in "${scripts[@]}"; do
        if [[ ${existing} == "${f}" ]]; then
          duplicate=1
          break
        fi
      done
    fi
    if ((duplicate == 0)); then
      scripts+=("${f}")
    fi
  done <"${collection_file}"

  ((${#scripts[@]} >= 1)) || die "no supported shell files found in the given paths"

  local failures=0 parser script
  for script in "${scripts[@]}"; do
    log "==> ${script}"

    parser="$(syntax_parser "${script}")"
    if ! "${parser}" -n -- "${script}"; then
      log "  [FAIL] ${parser} -n (syntax)"
      ((failures++))
    else
      log "  [ok]   ${parser} -n"
    fi

    if ((run_shellcheck && have_shellcheck)); then
      if shellcheck -- "${script}"; then
        log "  [ok]   shellcheck"
      else
        log "  [FAIL] shellcheck"
        ((failures++))
      fi
    elif [[ ${parser} != bash ]]; then
      log "  [warn] portability: NOT CHECKED (ShellCheck skipped or unavailable)"
    fi

    if ((run_shfmt && have_shfmt)); then
      if ((fix)); then
        if shfmt -i 2 -ci -w -- "${script}"; then
          log "  [ok]   shfmt -w (formatted)"
        else
          log "  [FAIL] shfmt -w"
          ((failures++))
        fi
      elif shfmt -i 2 -ci -d -- "${script}"; then
        log "  [ok]   shfmt (formatted)"
      else
        log "  [FAIL] shfmt — run with --fix or 'shfmt -i 2 -ci -w'"
        ((failures++))
      fi
    fi
  done

  log ""
  if ((failures == 0)); then
    log "All requested checks passed (${#scripts[@]} file(s))."
    return 0
  fi
  log "${failures} check(s) failed across ${#scripts[@]} file(s)."
  return 1
}

main "$@"
