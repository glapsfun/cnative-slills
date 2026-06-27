#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly SCAFFOLD="${SCRIPT_DIR}/../scripts/bash-scaffold.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bash-scaffold-evals.XXXXXX")" || exit 1
readonly TEST_TMPDIR
readonly GENERATED="${TEST_TMPDIR}/generated.sh"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

failures=0
tests=0

run_test() {
  local name=$1
  local test_function=$2

  tests=$((tests + 1))
  if "${test_function}"; then
    printf 'ok - %s\n' "${name}"
  else
    printf 'not ok - %s\n' "${name}"
    failures=$((failures + 1))
  fi
}

test_generated_output_passes_bash_n() {
  bash -n "${GENERATED}"
}

test_sourcing_preserves_shell_state() {
  bash -c '
    before_flags=$-
    if shopt -qo pipefail; then
      before_pipefail=on
    else
      before_pipefail=off
    fi
    before_ifs=$IFS
    before_exit=$(trap -p EXIT)
    before_int=$(trap -p INT)
    before_term=$(trap -p TERM)

    source "$1"

    [[ $- == "$before_flags" ]] || exit 1
    if shopt -qo pipefail; then
      after_pipefail=on
    else
      after_pipefail=off
    fi
    [[ $after_pipefail == "$before_pipefail" ]] || exit 1
    [[ $IFS == "$before_ifs" ]] || exit 1
    [[ $(trap -p EXIT) == "$before_exit" ]] || exit 1
    [[ $(trap -p INT) == "$before_int" ]] || exit 1
    [[ $(trap -p TERM) == "$before_term" ]] || exit 1
  ' _ "${GENERATED}"
}

test_repeated_sourcing_preserves_runtime_globals() {
  bash -c '
    set -e
    SCRIPT_DIR=caller-script-dir
    SCRIPT_NAME=caller-script-name

    source "$1"
    source "$1"

    [[ $SCRIPT_DIR == caller-script-dir ]]
    [[ $SCRIPT_NAME == caller-script-name ]]
  ' _ "${GENERATED}"
}

test_log_preserves_argument_boundaries_on_one_line() {
  local line
  local output

  output="$(bash -c 'source "$1"; log INFO alpha beta; printf "__END__"' _ "${GENERATED}" 2>&1)" || return 1
  [[ ${output} == *$'\n'"__END__" ]] || return 1
  line=${output%$'\n'__END__}
  [[ ${line} != *$'\n'* ]] || return 1
  [[ ${line} == *"[INFO] alpha beta" ]]
}

test_log_shell_escapes_complex_arguments() {
  local expected
  local line
  local output

  expected="[INFO] alpha\\ beta \$'line\\nbreak' '' \\*"
  output="$(bash -c 'source "$1"; log INFO "$2" "$3" "$4" "$5"; printf "__END__"' _ \
    "${GENERATED}" "alpha beta" $'line\nbreak' "" "*" 2>&1)" || return 1
  [[ ${output} == *$'\n'"__END__" ]] || return 1
  line=${output%$'\n'__END__}
  [[ ${line} != *$'\n'* ]] || return 1
  [[ ${line} == *"${expected}" ]]
}

test_dry_run_shell_escapes_arguments_on_one_line() {
  local output

  output="$(bash -c 'source "$1"; DRY_RUN=1; run "alpha beta" "*"; printf "__END__"' _ "${GENERATED}" 2>&1)" || return 1
  [[ ${output} == 'DRY-RUN: alpha\ beta \*'$'\n''__END__' ]]
}

test_int_trap_exits_130() {
  bash -c 'source "$1"; install_traps; kill -INT "$$"' _ "${GENERATED}"
  [[ $? -eq 130 ]]
}

test_term_trap_exits_143() {
  bash -c 'source "$1"; install_traps; kill -TERM "$$"' _ "${GENERATED}"
  [[ $? -eq 143 ]]
}

test_direct_execution_initializes_before_traps_and_main() {
  local generated_content

  generated_content=$(<"${GENERATED}")
  # shellcheck disable=SC2016  # Generated variable references must remain literal in this source assertion.
  [[ ${generated_content} == *'if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -Eeuo pipefail
  initialize_runtime
  install_traps
  main "$@"
fi'* ]]
}

bash "${SCAFFOLD}" --name regression-test >"${GENERATED}" || {
  printf 'failed to generate scaffold\n' >&2
  exit 1
}

run_test "generated output passes bash -n" test_generated_output_passes_bash_n
run_test "sourcing preserves shell state" test_sourcing_preserves_shell_state
run_test "repeated sourcing preserves runtime globals" test_repeated_sourcing_preserves_runtime_globals
run_test "log preserves argument boundaries on one line" test_log_preserves_argument_boundaries_on_one_line
run_test "log shell-escapes complex arguments" test_log_shell_escapes_complex_arguments
run_test "dry-run shell-escapes arguments on one line" test_dry_run_shell_escapes_arguments_on_one_line
run_test "INT trap exits 130" test_int_trap_exits_130
run_test "TERM trap exits 143" test_term_trap_exits_143
run_test "direct execution initializes before traps and main" test_direct_execution_initializes_before_traps_and_main

printf '%d tests, %d failures\n' "${tests}" "${failures}"
((failures == 0))
