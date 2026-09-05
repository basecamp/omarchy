#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command script
require_command timeout

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
call_log="$test_tmp/calls"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/uname" <<'STUB'
#!/bin/bash
[[ ${1:-} == "-r" ]] || exit 97
printf '__omarchy_test_kernel_that_is_not_installed__\n'
STUB

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ ${1:-} == "-Qo" ]] || exit 97
exit 0
STUB

cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
stdin_tty=no
stdout_tty=no
[[ -t 0 ]] && stdin_tty=yes
[[ -t 1 ]] && stdout_tty=yes
printf 'gum stdin=%s stdout=%s unattended=%s args=%s\n' \
  "$stdin_tty" "$stdout_tty" "${OMARCHY_UPDATE_UNATTENDED:-}" "$*" >>"$CALL_LOG"
exit 1
STUB

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
[[ $* == "-x Hyprland" ]] || exit 97
exit 1
STUB

cat >"$stub_bin/omarchy-system-reboot" <<'STUB'
#!/bin/bash
printf 'unexpected reboot\n' >>"$CALL_LOG"
exit 97
STUB

cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash
printf 'unexpected state call: %s\n' "$*" >>"$CALL_LOG"
exit 97
STUB

cat >"$stub_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
printf 'shell restart\n' >>"$CALL_LOG"
exit 0
STUB

chmod +x "$stub_bin"/*

run_restart() { # terminal(0|1) unattended(0|1)
  : >"$call_log"
  local environment=(
    "HOME=$test_home"
    "PATH=$stub_bin:/usr/bin:/bin"
    "CALL_LOG=$call_log"
    "TERM=dumb"
  )
  (( $2 == 0 )) || environment+=("OMARCHY_UPDATE_UNATTENDED=1")

  if (( $1 == 1 )); then
    env -i "${environment[@]}" timeout 3 \
      script -qec "bash '$ROOT/bin/omarchy-update-restart'" "$test_tmp/transcript" \
      </dev/null >"$test_tmp/out" 2>"$test_tmp/err"
  else
    env -i "${environment[@]}" timeout 3 \
      bash "$ROOT/bin/omarchy-update-restart" \
      </dev/null >"$test_tmp/out" 2>"$test_tmp/err"
  fi
}

assert_no_system_call() {
  if grep -q '^unexpected ' "$call_log"; then
    fail "$1 reaches a system-affecting stub" "$(<"$call_log")"
  fi
}

run_restart 1 0 || fail "interactive restart check completes against harmless stubs"
grep -Fqx 'gum stdin=yes stdout=yes unattended= args=confirm Linux kernel has been updated. Reboot?' "$call_log" ||
  fail "interactive restart check does not reach gum on the update pseudo-terminal" "$(<"$call_log")"
assert_no_system_call "interactive restart check"
pass "interactive restart check offers the reboot on the update pseudo-terminal"

run_restart 1 1 || fail "unattended restart check completes against harmless stubs"
if grep -q '^gum ' "$call_log"; then
  fail "-y reaches the post-update reboot prompt" "$(<"$call_log")"
fi
grep -q 'Linux kernel has been updated' "$test_tmp/out" ||
  fail "-y does not report that a reboot is needed" "$(<"$test_tmp/out")"
assert_no_system_call "unattended restart check"
pass "-y reports the required reboot without asking"

run_restart 0 0 || fail "headless restart check completes against harmless stubs"
if grep -q '^gum ' "$call_log"; then
  fail "headless restart check reaches a prompt nobody can answer" "$(<"$call_log")"
fi
grep -q 'Linux kernel has been updated' "$test_tmp/out" ||
  fail "headless restart check does not report that a reboot is needed" "$(<"$test_tmp/out")"
assert_no_system_call "headless restart check"
pass "headless restart check reports the required reboot without asking"
