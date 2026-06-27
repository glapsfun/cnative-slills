#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly SCAFFOLD="${SCRIPT_DIR}/../scripts/bash-scaffold.sh"
readonly LINTER="${SCRIPT_DIR}/../scripts/bash-lint.sh"
readonly DOC_DISCOVER="${SCRIPT_DIR}/../scripts/bash-doc-discover.sh"
readonly VERSION_CHECK="${SCRIPT_DIR}/../scripts/bash-version-check.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bash-scaffold-evals.XXXXXX")" || exit 1
readonly TEST_TMPDIR
readonly GENERATED="${TEST_TMPDIR}/generated.sh"
readonly LINT_FIXTURES="${TEST_TMPDIR}/lint-fixtures"
readonly ENV_S_FIXTURES="${TEST_TMPDIR}/env-s-fixtures"
readonly ATTACHED_ENV_S_SH_FIXTURES="${TEST_TMPDIR}/attached-env-s-sh-fixtures"
readonly ATTACHED_ENV_S_BASH_FIXTURES="${TEST_TMPDIR}/attached-env-s-bash-fixtures"
readonly HYPHEN_FIXTURES="${TEST_TMPDIR}/hyphen-fixtures"
readonly NEWLINE_FIXTURES="${TEST_TMPDIR}/newline-fixtures"$'\n'
readonly TRAILING_NEWLINE_FILE="${NEWLINE_FIXTURES}/runner"$'\n'
readonly FAKE_FIND_BIN="${TEST_TMPDIR}/fake-find-bin"
readonly FAKE_LEADING_BIN="${TEST_TMPDIR}/fake-leading-bin"
readonly FAKE_SHFMT_BIN="${TEST_TMPDIR}/fake-shfmt-bin"
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

assert_unexpected_argument() {
  local helper=$1
  local expected_argument=$2
  local expected_stderr_file="${TEST_TMPDIR}/helper-expected-stderr"
  local stdout_file="${TEST_TMPDIR}/helper-stdout"
  local stderr_file="${TEST_TMPDIR}/helper-stderr"
  local status
  shift 2

  printf 'error: unexpected argument: %s\n' "${expected_argument}" >"${expected_stderr_file}"
  bash "${helper}" "$@" >"${stdout_file}" 2>"${stderr_file}"
  status=$?

  [[ ${status} -eq 2 ]] || return 1
  [[ ! -s ${stdout_file} ]] || return 1
  cmp -s "${expected_stderr_file}" "${stderr_file}"
}

assert_help_options() {
  local helper=$1
  local option
  local output
  local stderr_file="${TEST_TMPDIR}/helper-stderr"

  for option in -h --help; do
    output="$(bash "${helper}" "${option}" 2>"${stderr_file}")" || return 1
    [[ ${output} == Usage:* ]] || return 1
    [[ ! -s ${stderr_file} ]] || return 1
  done
}

test_doc_discover_rejects_unexpected_argument() {
  assert_unexpected_argument "${DOC_DISCOVER}" unexpected unexpected
}

test_version_check_rejects_unexpected_argument() {
  assert_unexpected_argument "${VERSION_CHECK}" unexpected unexpected
}

test_doc_discover_rejects_multiple_unexpected_arguments() {
  assert_unexpected_argument "${DOC_DISCOVER}" unexpected unexpected another
}

test_version_check_rejects_multiple_unexpected_arguments() {
  assert_unexpected_argument "${VERSION_CHECK}" unexpected unexpected another
}

test_doc_discover_help_options() {
  assert_help_options "${DOC_DISCOVER}"
}

test_version_check_help_options() {
  assert_help_options "${VERSION_CHECK}"
}

test_doc_discover_rejects_arguments_after_help() {
  assert_unexpected_argument "${DOC_DISCOVER}" unexpected --help unexpected
}

test_version_check_rejects_arguments_after_help() {
  assert_unexpected_argument "${VERSION_CHECK}" unexpected --help unexpected
}

test_doc_discover_uses_current_posix_issue() {
  local output

  output="$(bash "${DOC_DISCOVER}")" || return 1
  [[ ${output} == *"https://pubs.opengroup.org/onlinepubs/9799919799/"* ]] || return 1
  [[ ${output} != *"9699919799"* ]]
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

test_generated_cleanup_preserves_original_exit_status() {
  local generated_content

  generated_content=$(<"${GENERATED}")
  # shellcheck disable=SC2016  # Generated variable references must remain literal in this source assertion.
  [[ ${generated_content} == *'cleanup_resources() {
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
}'* ]]
}

test_generated_cleanup_failure_preserves_original_exit_status() {
  local stdout_file="${TEST_TMPDIR}/cleanup-stdout"
  local stderr_file="${TEST_TMPDIR}/cleanup-stderr"
  local status

  bash -c '
    source "$1"
    set -e
    cleanup_resources() { return 9; }
    install_traps
    exit 7
  ' _ "${GENERATED}" >"${stdout_file}" 2>"${stderr_file}"
  status=$?

  [[ ${status} -eq 7 ]] || return 1
  [[ ! -s ${stdout_file} ]] || return 1
  grep -q 'cleanup.*failed' "${stderr_file}"
}

test_generated_cleanup_warning_failure_preserves_original_exit_status() {
  local stdout_file="${TEST_TMPDIR}/cleanup-warning-stdout"
  local stderr_file="${TEST_TMPDIR}/cleanup-warning-stderr"
  local status

  bash -c '
    source "$1"
    set -e
    cleanup_resources() { return 9; }
    log_warn() {
      printf "forced cleanup warning\n" >&2
      return 8
    }
    install_traps
    exit 7
  ' _ "${GENERATED}" >"${stdout_file}" 2>"${stderr_file}"
  status=$?

  [[ ${status} -eq 7 ]] || return 1
  [[ ! -s ${stdout_file} ]] || return 1
  grep -q 'forced cleanup warning' "${stderr_file}"
}

test_linter_discovers_supported_directory_scripts() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${LINT_FIXTURES}" 2>&1
  )" || return 1

  [[ ${output} == *"==> ${LINT_FIXTURES}/sample.sh"* ]] || return 1
  [[ ${output} == *"==> ${LINT_FIXTURES}/sample.bash"* ]] || return 1
  [[ ${output} == *"==> ${LINT_FIXTURES}/runner"* ]] || return 1
  [[ ${output} != *"==> ${LINT_FIXTURES}/not-a-shell-file.txt"* ]] || return 1
  [[ ${output} != *"==> ${LINT_FIXTURES}/non-executable"* ]] || return 1
  [[ $(printf '%s\n' "${output}" | grep -c '^==> ') -eq 3 ]] || return 1
  [[ ${output} == *"All requested checks passed (3 file(s))."* ]]
}

test_linter_uses_sh_for_posix_shebang() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${LINT_FIXTURES}/sample.sh" 2>&1
  )" || return 1

  [[ ${output} == *"[ok]   sh -n"* ]] || return 1
  [[ ${output} != *"[ok]   bash -n"* ]]
}

test_linter_warns_when_posix_portability_is_not_checked() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${LINT_FIXTURES}/sample.sh" 2>&1
  )" || return 1

  [[ ${output} == *"[warn] portability: NOT CHECKED (ShellCheck skipped or unavailable)"* ]]
}

test_linter_reports_missing_path_once() {
  local missing="${TEST_TMPDIR}/does-not-exist"
  local output
  local status

  output="$(bash "${LINTER}" --no-shellcheck --no-shfmt "${missing}" 2>&1)"
  status=$?

  [[ ${status} -eq 2 ]] || return 1
  [[ ${output} == "error: no such file or directory: ${missing}" ]] || return 1
  [[ $(printf '%s\n' "${output}" | grep -c '^error: ') -eq 1 ]]
}

test_linter_decodes_env_s_shebangs() {
  local dash_parser=sh
  local output

  command -v dash >/dev/null 2>&1 && dash_parser=dash
  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${ENV_S_FIXTURES}" 2>&1
  )" || return 1

  [[ ${output} == *"==> ${ENV_S_FIXTURES}/env-s-sh"* ]] || return 1
  [[ ${output} == *"==> ${ENV_S_FIXTURES}/env-s-bash"* ]] || return 1
  [[ ${output} == *"==> ${ENV_S_FIXTURES}/env-s-dash"* ]] || return 1
  [[ $(printf '%s\n' "${output}" | grep -c '^==> ') -eq 3 ]] || return 1
  [[ $(printf '%s\n' "${output}" | grep -c '\[ok\]   bash -n') -eq 1 ]] || return 1
  if [[ ${dash_parser} == dash ]]; then
    [[ $(printf '%s\n' "${output}" | grep -c '\[ok\]   sh -n') -eq 1 ]] || return 1
    [[ $(printf '%s\n' "${output}" | grep -c '\[ok\]   dash -n') -eq 1 ]] || return 1
  else
    [[ $(printf '%s\n' "${output}" | grep -c '\[ok\]   sh -n') -eq 2 ]] || return 1
  fi
  [[ $(printf '%s\n' "${output}" | grep -c 'portability: NOT CHECKED') -eq 2 ]]
}

test_linter_decodes_attached_env_s_sh() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${ATTACHED_ENV_S_SH_FIXTURES}" 2>&1
  )" || return 1

  [[ ${output} == *"==> ${ATTACHED_ENV_S_SH_FIXTURES}/runner"* ]] || return 1
  [[ ${output} == *"[ok]   sh -n"* ]] || return 1
  [[ ${output} != *"[ok]   bash -n"* ]] || return 1
  [[ ${output} == *"[warn] portability: NOT CHECKED (ShellCheck skipped or unavailable)"* ]]
}

test_linter_decodes_attached_env_s_bash() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${ATTACHED_ENV_S_BASH_FIXTURES}" 2>&1
  )" || return 1

  [[ ${output} == *"==> ${ATTACHED_ENV_S_BASH_FIXTURES}/runner"* ]] || return 1
  [[ ${output} == *"[ok]   bash -n"* ]] || return 1
  [[ ${output} != *"portability: NOT CHECKED"* ]]
}

test_linter_fails_closed_when_find_fails() {
  local output
  local status

  output="$(
    PATH="${FAKE_FIND_BIN}:${PATH}" \
      bash "${LINTER}" --no-shellcheck --no-shfmt "${LINT_FIXTURES}" 2>&1
  )"
  status=$?

  [[ ${status} -eq 2 ]] || return 1
  [[ ${output} == "error: failed to search directory: ${LINT_FIXTURES}" ]] || return 1
  [[ $(printf '%s\n' "${output}" | grep -c '^error: ') -eq 1 ]]
}

test_linter_handles_direct_leading_hyphen_file() {
  local output
  local status

  output="$(
    cd "${HYPHEN_FIXTURES}" &&
      PATH="${FAKE_LEADING_BIN}:${PATH}" bash "${LINTER}" -- -n 2>&1
  )"
  status=$?

  [[ ${status} -eq 1 ]] || return 1
  [[ ${output} == *"[FAIL] bash -n (syntax)"* ]] || return 1
  [[ ${output} == *"[FAIL] shellcheck"* ]] || return 1
  [[ ${output} == *"[FAIL] shfmt"* ]]
}

test_linter_handles_discovered_leading_hyphen_file() {
  local output
  local status

  output="$(
    cd "${HYPHEN_FIXTURES}" &&
      PATH="${FAKE_LEADING_BIN}:${PATH}" bash "${LINTER}" . 2>&1
  )"
  status=$?

  [[ ${status} -eq 1 ]] || return 1
  [[ ${output} == *"[FAIL] bash -n (syntax)"* ]] || return 1
  [[ ${output} == *"[FAIL] shellcheck"* ]] || return 1
  [[ ${output} == *"[FAIL] shfmt"* ]]
}

test_linter_reports_failed_shfmt_fix() {
  local output
  local status

  output="$(
    PATH="${FAKE_SHFMT_BIN}:${PATH}" \
      bash "${LINTER}" --no-shellcheck --fix "${LINT_FIXTURES}/sample.bash" 2>&1
  )"
  status=$?

  [[ ${status} -eq 1 ]] || return 1
  [[ ${output} == *"[FAIL] shfmt -w"* ]] || return 1
  [[ ${output} != *"All requested checks passed"* ]]
}

test_linter_deduplicates_overlapping_inputs() {
  local output

  output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt \
      "${LINT_FIXTURES}" "${LINT_FIXTURES}/sample.sh" 2>&1
  )" || return 1

  [[ $(printf '%s\n' "${output}" | grep -c '^==> ') -eq 3 ]] || return 1
  [[ ${output} == *"All requested checks passed (3 file(s))."* ]]
}

test_linter_preserves_trailing_newline_pathnames() {
  local discovered_output
  local explicit_output

  discovered_output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${NEWLINE_FIXTURES}" 2>&1
  )" || return 1
  explicit_output="$(
    bash "${LINTER}" --no-shellcheck --no-shfmt "${TRAILING_NEWLINE_FILE}" 2>&1
  )" || return 1

  [[ ${discovered_output} == *"All requested checks passed (1 file(s))."* ]] || return 1
  [[ ${explicit_output} == *"All requested checks passed (1 file(s))."* ]]
}

mkdir -p "${LINT_FIXTURES}" "${ENV_S_FIXTURES}" \
  "${ATTACHED_ENV_S_SH_FIXTURES}" "${ATTACHED_ENV_S_BASH_FIXTURES}" \
  "${HYPHEN_FIXTURES}" "${NEWLINE_FIXTURES}" \
  "${FAKE_FIND_BIN}" "${FAKE_LEADING_BIN}" "${FAKE_SHFMT_BIN}" || exit 1
cat >"${LINT_FIXTURES}/sample.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "sample.sh"
EOF
cat >"${LINT_FIXTURES}/sample.bash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "sample.bash"
EOF
cat >"${LINT_FIXTURES}/runner" <<'EOF'
#!/usr/bin/env dash
printf '%s\n' "runner"
EOF
cat >"${LINT_FIXTURES}/not-a-shell-file.txt" <<'EOF'
not a shell script
EOF
cat >"${LINT_FIXTURES}/non-executable" <<'EOF'
#!/bin/sh
printf '%s\n' "not executable"
EOF
chmod +x "${LINT_FIXTURES}/runner"

cat >"${ENV_S_FIXTURES}/env-s-sh" <<'EOF'
#!/usr/bin/env -S sh -eu
printf '%s\n' "env -S sh"
EOF
cat >"${ENV_S_FIXTURES}/env-s-bash" <<'EOF'
#!/usr/bin/env -S bash -eu
printf '%s\n' "env -S bash"
EOF
cat >"${ENV_S_FIXTURES}/env-s-dash" <<'EOF'
#!/usr/bin/env -S dash -eu
printf '%s\n' "env -S dash"
EOF
chmod +x "${ENV_S_FIXTURES}/env-s-sh" "${ENV_S_FIXTURES}/env-s-bash" \
  "${ENV_S_FIXTURES}/env-s-dash"

cat >"${ATTACHED_ENV_S_SH_FIXTURES}/runner" <<'EOF'
#!/usr/bin/env -Ssh -eu
printf '%s\n' "env -Ssh"
EOF
cat >"${ATTACHED_ENV_S_BASH_FIXTURES}/runner" <<'EOF'
#!/usr/bin/env -Sbash -eu
printf '%s\n' "env -Sbash"
EOF
chmod +x "${ATTACHED_ENV_S_SH_FIXTURES}/runner" "${ATTACHED_ENV_S_BASH_FIXTURES}/runner"

cat >"${HYPHEN_FIXTURES}/-n" <<'EOF'
#!/usr/bin/env bash
if then
EOF
chmod +x "${HYPHEN_FIXTURES}/-n"

cat >"${TRAILING_NEWLINE_FILE}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "trailing newline"
EOF
chmod +x "${TRAILING_NEWLINE_FILE}"

cat >"${FAKE_FIND_BIN}/find" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$1/sample.sh"
exit 7
EOF
chmod +x "${FAKE_FIND_BIN}/find"

cat >"${FAKE_LEADING_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
last=''
for argument in "$@"; do
  last=${argument}
done
[[ ${last} == ./-n ]] || exit 0
exit 7
EOF
cat >"${FAKE_LEADING_BIN}/shfmt" <<'EOF'
#!/usr/bin/env bash
last=''
for argument in "$@"; do
  last=${argument}
done
[[ ${last} == ./-n ]] || exit 0
exit 7
EOF
chmod +x "${FAKE_LEADING_BIN}/shellcheck" "${FAKE_LEADING_BIN}/shfmt"

cat >"${FAKE_SHFMT_BIN}/shfmt" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "${FAKE_SHFMT_BIN}/shfmt"

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
run_test "generated cleanup preserves the original exit status" test_generated_cleanup_preserves_original_exit_status
run_test "generated cleanup failure preserves the original exit status" test_generated_cleanup_failure_preserves_original_exit_status
run_test "generated cleanup warning failure preserves the original exit status" test_generated_cleanup_warning_failure_preserves_original_exit_status
run_test "linter discovers supported directory scripts" test_linter_discovers_supported_directory_scripts
run_test "linter uses sh for POSIX shebang" test_linter_uses_sh_for_posix_shebang
run_test "linter warns when POSIX portability is not checked" test_linter_warns_when_posix_portability_is_not_checked
run_test "linter reports a missing path once" test_linter_reports_missing_path_once
run_test "linter decodes env -S shebangs" test_linter_decodes_env_s_shebangs
run_test "linter decodes attached env -Ssh" test_linter_decodes_attached_env_s_sh
run_test "linter decodes attached env -Sbash" test_linter_decodes_attached_env_s_bash
run_test "linter fails closed when find fails" test_linter_fails_closed_when_find_fails
run_test "linter handles a direct leading-hyphen file" test_linter_handles_direct_leading_hyphen_file
run_test "linter handles a discovered leading-hyphen file" test_linter_handles_discovered_leading_hyphen_file
run_test "linter reports failed shfmt --fix" test_linter_reports_failed_shfmt_fix
run_test "linter deduplicates overlapping inputs" test_linter_deduplicates_overlapping_inputs
run_test "linter preserves trailing-newline pathnames" test_linter_preserves_trailing_newline_pathnames
run_test "doc discovery rejects an unexpected argument" test_doc_discover_rejects_unexpected_argument
run_test "version check rejects an unexpected argument" test_version_check_rejects_unexpected_argument
run_test "doc discovery rejects multiple unexpected arguments" test_doc_discover_rejects_multiple_unexpected_arguments
run_test "version check rejects multiple unexpected arguments" test_version_check_rejects_multiple_unexpected_arguments
run_test "doc discovery supports both help options" test_doc_discover_help_options
run_test "version check supports both help options" test_version_check_help_options
run_test "doc discovery rejects arguments after help" test_doc_discover_rejects_arguments_after_help
run_test "version check rejects arguments after help" test_version_check_rejects_arguments_after_help
run_test "doc discovery uses the current POSIX issue" test_doc_discover_uses_current_posix_issue

printf '%d tests, %d failures\n' "${tests}" "${failures}"
((failures == 0))
