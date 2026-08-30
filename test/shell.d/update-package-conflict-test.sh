#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command script

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
helper_copy="$test_tmp/omarchy-update-file-conflicts"
system_pkgs_copy="$stub_bin/omarchy-update-system-pkgs"
mkdir -p "$stub_bin"

test_uid=$(id -u)
test_gid=$(id -g)
sed \
  -e 's/if ((EUID != 0)); then/if false; then/' \
  -e 's|export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin|export PATH=${OMARCHY_TEST_HELPER_PATH:?}|' \
  -e 's/readonly ROOT_UID=0/readonly ROOT_UID='"$test_uid"'/' \
  -e 's/readonly ROOT_GID=0/readonly ROOT_GID='"$test_gid"'/' \
  -e "s|readonly REPORT_PARENT=/run|readonly REPORT_PARENT=$test_tmp|" \
  "$ROOT/bin/omarchy-update-file-conflicts" >"$helper_copy"
chmod +x "$helper_copy"

sed \
  -e "s|/usr/bin/omarchy-update-file-conflicts|$helper_copy|g" \
  -e "s|/usr/bin/pacman|$stub_bin/pacman|g" \
  "$ROOT/bin/omarchy-update-system-pkgs" >"$system_pkgs_copy"
chmod +x "$system_pkgs_copy"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "$TEST_CONFLICT_HELPER" ]]; then
  shift
  exec env OMARCHY_TEST_ROOT_HELPER=1 "$TEST_CONFLICT_HELPER" "$@"
fi
if [[ ${1:-} == /usr/bin/env && ${2:-} == OMARCHY_UPDATE_PACMAN=1 && ${3:-} == "$TEST_PACMAN" ]]; then
  exec "$@"
fi
echo "unexpected sudo command: $*" >&2
exit 97
STUB

# Fails the first -Syu with the report under test, then succeeds. Every call
# records its arguments and which of its streams reached a terminal: pacman puts
# its questions on stderr once it is not running --noconfirm, so a retry meant
# for a person has to keep that stream.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
attempt=$(($(cat "$PACMAN_ATTEMPTS") + 1))
echo "$attempt" >"$PACMAN_ATTEMPTS"
{
  printf 'args %s\n' "$*"
  if [[ ${OMARCHY_TEST_ROOT_HELPER:-} == 1 ]]; then
    printf 'root-helper yes\n'
  else
    printf 'root-helper no\n'
  fi
  for fd in 0 1 2; do
    if [[ -t $fd ]]; then printf 'tty%s yes\n' "$fd"; else printf 'tty%s no\n' "$fd"; fi
  done
} >>"$PACMAN_CALLS"

if ((attempt == 1)); then
  cat "$CONFLICT_REPORT" >&2
  exit 1
fi
echo "upgrade complete"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/pacman"

# Everything a blocked qemu-common upgrade leaves on stderr, and no more. The
# ":: ... Remove qemu-block-gluster? [y/N]" pacman asked is deliberately absent:
# under --noconfirm it goes to stdout, so nothing downstream of the report can
# be built on having read it.
write_conflict_report() {
  echo 0 >"$test_tmp/attempts"
  : >"$test_tmp/calls"
  {
    printf '\e[1;31merror: \e[0munresolvable package conflicts detected\n'
    printf '\e[1;31merror: \e[0mfailed to prepare transaction (conflicting dependencies)\n'
  } >"$test_tmp/report"
}

update_env() {
  printf '%s\n' \
    "OMARCHY_REPLACED_DIR=$test_tmp/replaced" \
    "PACMAN_ATTEMPTS=$test_tmp/attempts" \
    "PACMAN_CALLS=$test_tmp/calls" \
    "CONFLICT_REPORT=$test_tmp/report" \
    "TEST_CONFLICT_HELPER=$helper_copy" \
    "TEST_PACMAN=$stub_bin/pacman" \
    "OMARCHY_TEST_HELPER_PATH=$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin" \
    "OWNED_PATHS=" \
    "OMARCHY_UPDATE_UNATTENDED=${OMARCHY_UPDATE_UNATTENDED:-}" \
    "OMARCHY_UPDATE_INTERACTIVE=${OMARCHY_UPDATE_INTERACTIVE:-}" \
    "PATH=$stub_bin:$ROOT/bin:$PATH"
}

# No terminal on any stream, the way a cron or ssh caller arrives.
run_headless() {
  mapfile -t environment < <(update_env)
    env "${environment[@]}" bash "$system_pkgs_copy" \
    </dev/null >"$test_tmp/out" 2>"$test_tmp/err"
}

# script gives the update the pty that omarchy-update always runs it on, so the
# terminal checks see what a person at the keyboard would give them. Its
# transcript is stdout and stderr together, which is also what that person sees.
# $1 optionally takes one stream back off the pty.
run_on_terminal() {
  mapfile -t environment < <(update_env)
  env "${environment[@]}" \
    script -qec "bash '$system_pkgs_copy' ${1:-}" "$test_tmp/out" >/dev/null 2>&1
}

call_line() {
  awk -v call="$1" -v key="$2" \
    '$1 == "args" { n++ } n == call && $1 == key { sub(/^[^ ]+ /, ""); print }' "$test_tmp/calls"
}

write_conflict_report
run_on_terminal ||
  fail "a package conflict is not resolved on a terminal" "$(cat "$test_tmp/out" "$test_tmp/calls")"
(($(cat "$test_tmp/attempts") == 2)) ||
  fail "a package conflict does not get an interactive retry"
[[ $(call_line 1 args) == "-Syu "* ]] ||
  fail "the report-authorizing transaction does not refresh package databases"
[[ $(call_line 2 args) == "-Su "* ]] ||
  fail "the interactive retry refreshes or changes the authorized transaction"
[[ $(call_line 2 args) != *"--noconfirm"* ]] ||
  fail "the interactive retry still answers pacman's questions itself"
[[ $(call_line 2 args) != *"--ask"* ]] ||
  fail "the interactive retry answers pacman's questions from a bitmask instead"
[[ $(call_line 1 root-helper) == yes ]] ||
  fail "the report-authorizing transaction is not owned by the root helper"
[[ $(call_line 2 root-helper) == no ]] ||
  fail "the interactive package retry unexpectedly enters the file-mutation helper"
[[ -z $(find "$test_tmp" -maxdepth 1 -type d -name 'omarchy-update-pacman.*' -print -quit) ]] ||
  fail "the package-conflict handoff leaves its privileged report behind"
pass "a package conflict is put back to the person running the update"

[[ $(call_line 2 tty0) == "yes" && $(call_line 2 tty2) == "yes" ]] ||
  fail "the interactive retry cannot be answered: pacman has no terminal left"
pass "the interactive retry keeps the streams pacman asks and listens on"

# Which streams have to be a terminal follows from where pacman asks: stderr
# carries the question once --noconfirm is gone, stdin carries the answer, and
# stdout carries progress bars nobody has to see to answer.
write_conflict_report
run_on_terminal '>/dev/null' ||
  fail "a redirected progress stream is mistaken for an unattended update"
(($(cat "$test_tmp/attempts") == 2)) ||
  fail "a conflict goes unasked when only stdout is redirected"
pass "an answerable session is not turned away over its progress output"

write_conflict_report
if run_on_terminal '2>/dev/null'; then
  fail "a conflict is asked about on a stream nobody is reading"
fi
(($(cat "$test_tmp/attempts") == 1)) ||
  fail "pacman is left prompting where the question cannot be seen"
pass "a session that cannot show the question is not asked one"

[[ $(call_line 1 tty2) == "no" ]] ||
  fail "the first upgrade no longer captures the error report"
pass "the first upgrade still captures its errors for the handler"

write_conflict_report
if run_headless; then
  fail "a package conflict passes for a completed update without a terminal"
fi
(($(cat "$test_tmp/attempts") == 1)) ||
  fail "a package conflict is retried with no terminal to answer on"
grep -q 'omarchy update' "$test_tmp/err" ||
  fail "a package conflict with no terminal does not say how to answer it"
pass "a package conflict with no terminal reports instead of hanging"

write_conflict_report
if OMARCHY_UPDATE_UNATTENDED=1 run_on_terminal; then
  fail "an unattended update stops on a prompt nobody answers"
fi
(($(cat "$test_tmp/attempts") == 1)) ||
  fail "an unattended update prompts anyway"
pass "-y is kept: an unattended update never waits on an answer"

# The interactive upgrade skips the error capture the handler depends on, so
# reaching it any other way would lose the report that drives every recovery.
write_conflict_report
if OMARCHY_UPDATE_INTERACTIVE=1 run_headless; then
  fail "a caller reaches the interactive upgrade on its own"
fi
[[ $(call_line 1 args) == *"--noconfirm"* ]] ||
  fail "a caller can ask for an interactive upgrade directly"
pass "only the conflict handler can hand the upgrade to a person"
