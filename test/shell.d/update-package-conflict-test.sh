#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command script

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/tmp"

# Fail closed on every privileged command shape except the two fixed Pacman
# invocations the updater is allowed to make.
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"

case "$*" in
  '/usr/bin/env LC_ALL=C OMARCHY_UPDATE_PACMAN=1 /usr/bin/pacman -Syu --noconfirm')
    exec "$PACMAN_STUB" -Syu --noconfirm
    ;;
  '/usr/bin/env OMARCHY_UPDATE_PACMAN=1 /usr/bin/pacman -Su')
    exec "$PACMAN_STUB" -Su
    ;;
  *)
    echo "unexpected privileged command: $*" >&2
    exit 97
    ;;
esac
STUB

# Fails the first update with the report under test, then succeeds. Every call
# records its arguments and which streams reached a terminal; Pacman asks on
# stderr and listens on stdin once --noconfirm is gone.
cat >"$stub_bin/pacman-stub" <<'STUB'
#!/bin/bash
attempt=$(($(<"$PACMAN_ATTEMPTS") + 1))
echo "$attempt" >"$PACMAN_ATTEMPTS"
{
  printf 'args %s\n' "$*"
  for fd in 0 1 2; do
    if [[ -t $fd ]]; then
      printf 'tty%s yes\n' "$fd"
    else
      printf 'tty%s no\n' "$fd"
    fi
  done
} >>"$PACMAN_CALLS"

if (( attempt == 1 )); then
  cat "$CONFLICT_REPORT" >&2
  exit "${FIRST_STATUS:-1}"
fi
echo 'upgrade complete'
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/pacman-stub"

write_package_conflict_report() {
  echo 0 >"$test_tmp/attempts"
  : >"$test_tmp/calls"
  : >"$test_tmp/sudo-calls"
  {
    printf '\e[1;31merror: \e[0munresolvable package conflicts detected\n'
    printf '\e[1;31merror: \e[0mfailed to prepare transaction (conflicting dependencies)\n'
  } >"$test_tmp/report"
}

write_unrelated_report() {
  echo 0 >"$test_tmp/attempts"
  : >"$test_tmp/calls"
  : >"$test_tmp/sudo-calls"
  echo 'error: failed retrieving file from mirror' >"$test_tmp/report"
}

update_env() {
  printf '%s\n' \
    "PACMAN_STUB=$stub_bin/pacman-stub" \
    "PACMAN_ATTEMPTS=$test_tmp/attempts" \
    "PACMAN_CALLS=$test_tmp/calls" \
    "SUDO_CALLS=$test_tmp/sudo-calls" \
    "CONFLICT_REPORT=$test_tmp/report" \
    "FIRST_STATUS=${FIRST_STATUS:-1}" \
    "TMPDIR=$test_tmp/tmp" \
    "OMARCHY_UPDATE_UNATTENDED=${OMARCHY_UPDATE_UNATTENDED:-}" \
    "PATH=$stub_bin:$ROOT/bin:$PATH"
}

run_headless() {
  mapfile -t environment < <(update_env)
  env "${environment[@]}" bash "$ROOT/bin/omarchy-update-system-pkgs" \
    </dev/null >"$test_tmp/out" 2>"$test_tmp/err"
}

run_on_terminal() {
  mapfile -t environment < <(update_env)
  env "${environment[@]}" \
    script -qec "bash '$ROOT/bin/omarchy-update-system-pkgs' ${1:-}" "$test_tmp/out" >/dev/null 2>&1
}

call_line() {
  awk -v call="$1" -v key="$2" \
    '$1 == "args" { n++ } n == call && $1 == key { sub(/^[^ ]+ /, ""); print }' "$test_tmp/calls"
}

assert_reports_cleaned() {
  [[ -z $(find "$test_tmp/tmp" -mindepth 1 -print -quit) ]] || fail "the package update leaks its error report"
}

write_package_conflict_report
run_on_terminal || fail "a package conflict is not resolved on a terminal"
(( $(<"$test_tmp/attempts") == 2 )) || fail "a package conflict does not get an interactive retry"
[[ $(call_line 1 args) == "-Syu --noconfirm" ]] || fail "the first package update changes the ordinary transaction"
[[ $(call_line 2 args) == "-Su" ]] || fail "the interactive retry is not the fixed no-refresh transaction"
[[ $(call_line 2 tty0) == "yes" && $(call_line 2 tty2) == "yes" ]] || fail "the interactive retry cannot be answered"
! grep -Eq -- '--overwrite|--ask' "$test_tmp/calls" || fail "a package-conflict retry answers or overwrites on the user's behalf"
assert_reports_cleaned
pass "a package conflict is put back to the person running the update"

write_package_conflict_report
run_on_terminal '>/dev/null' || fail "a redirected progress stream is mistaken for an unattended update"
(( $(<"$test_tmp/attempts") == 2 )) || fail "a conflict goes unasked when only stdout is redirected"
pass "an answerable session is not turned away over its progress output"

write_package_conflict_report
if run_on_terminal '2>/dev/null'; then
  fail "a conflict is asked about on a stream nobody is reading"
fi
(( $(<"$test_tmp/attempts") == 1 )) || fail "Pacman prompts where its question cannot be seen"
pass "a session that cannot show the question is not asked one"

write_package_conflict_report
if run_headless; then
  fail "a package conflict passes for a completed headless update"
fi
(( $(<"$test_tmp/attempts") == 1 )) || fail "a package conflict is retried without a terminal"
grep -q 'omarchy update' "$test_tmp/err" || fail "a headless conflict does not say how to answer it"
assert_reports_cleaned
pass "a package conflict with no terminal reports instead of hanging"

write_package_conflict_report
if OMARCHY_UPDATE_UNATTENDED=1 run_on_terminal; then
  fail "an unattended update stops on a prompt"
fi
(( $(<"$test_tmp/attempts") == 1 )) || fail "an unattended update prompts anyway"
pass "an unattended update never waits on an answer"

write_unrelated_report
if FIRST_STATUS=23 run_on_terminal; then
  fail "an unrelated Pacman failure reports success"
fi
(( $(<"$test_tmp/attempts") == 1 )) || fail "an unrelated Pacman failure is retried"
assert_reports_cleaned
pass "only a package conflict can trigger the fixed interactive retry"
