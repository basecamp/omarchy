#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
case ${1:-} in
  -v) exit "${SUDO_VALIDATE_RESULT:-0}" ;;
  -n) exit 0 ;;
esac
exec "$@"
STUB

# The sudo keepalive loop sleeps between refreshes, and its trap kills the loop
# without reaping an in-flight sleep. Keep the stub short so test runs do not
# leave a minute of stray sleeps behind. command -p skips the stub PATH.
cat >"$stub_bin/sleep" <<'STUB'
#!/bin/bash
command -p sleep 0.2
STUB

cat >"$stub_bin/fzf" <<'STUB'
#!/bin/bash
echo testpkg
STUB

cat >"$stub_bin/omarchy-show-done" <<'STUB'
#!/bin/bash
echo done >>"${CALL_LOG:?}"
STUB

cat >"$stub_bin/omarchy-show-error" <<'STUB'
#!/bin/bash
echo error >>"${CALL_LOG:?}"
STUB

cat >"$stub_bin/updatedb" <<'STUB'
#!/bin/bash
echo updatedb >>"${CALL_LOG:?}"
STUB

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
if [[ $1 == "-Slq" ]]; then
  echo testpkg
  exit 0
fi
echo "pacman $*" >>"${CALL_LOG:?}"
exit "${PACMAN_RESULT:-0}"
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
if [[ $1 == "-Slqa" ]]; then
  echo testpkg
  exit 0
fi
echo "yay $*" >>"${CALL_LOG:?}"
exit "${YAY_RESULT:-0}"
STUB

chmod +x "$stub_bin"/*

run_pkg_install() {
  : >"$call_log"
  CALL_LOG="$call_log" PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$TMPDIR/home" \
    bash "$ROOT/bin/omarchy-pkg-install" >/dev/null 2>&1
}

run_pkg_aur_install() {
  : >"$call_log"
  CALL_LOG="$call_log" PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$TMPDIR/home" \
    bash "$ROOT/bin/omarchy-pkg-aur-install" >/dev/null 2>&1
}

mkdir -p "$TMPDIR/home"

# A successful pacman run still reports done.
call_log="$TMPDIR/calls-success"
PACMAN_RESULT=0 run_pkg_install || fail "pkg-install exits clean on successful install"
grep -q '^done$' "$call_log" || fail "pkg-install reports done on successful install"
pass "pkg-install reports done on successful install"

# A pacman run that exits non-zero (dependency conflict, download failure, a
# declined sudo password) must not report done and must exit non-zero.
#
# Ctrl+C during the transaction is a different path and is deliberately not
# covered here: the tty sends SIGINT to the whole foreground process group, so
# bash takes it alongside pacman and dies before reaching either branch below.
# That already rules out a false done, and closing the window immediately is
# what a deliberate abort should do, so there is nothing for the script to
# handle. Stubbing an exit status cannot model signal delivery either way.
call_log="$TMPDIR/calls-abort"
if PACMAN_RESULT=130 run_pkg_install; then
  fail "pkg-install exits non-zero on aborted install"
fi
grep -q '^done$' "$call_log" && fail "pkg-install does not report done on aborted install"
pass "pkg-install does not report done on aborted install"
# The menu launches these in a throwaway terminal, so a failing transaction has
# to hold the window open or its output disappears before it can be read.
grep -q '^error$' "$call_log" || fail "pkg-install holds the terminal open on a failed install"
pass "pkg-install holds the terminal open on a failed install"

# An interrupt at the initial sudo validation (the first password prompt) must
# stop before the package transaction starts.
call_log="$TMPDIR/calls-sudo-abort"
if SUDO_VALIDATE_RESULT=130 run_pkg_install; then
  fail "pkg-install exits non-zero when sudo validation is interrupted"
fi
grep -q '^pacman ' "$call_log" && fail "pkg-install skips the pacman transaction when sudo validation is interrupted"
grep -q '^done$' "$call_log" && fail "pkg-install does not report done when sudo validation is interrupted"
pass "pkg-install aborts before the transaction when sudo validation is interrupted"
# The user asked to bail at the password prompt and there is nothing to read,
# so this path closes immediately instead of waiting for a keypress.
grep -q '^error$' "$call_log" && fail "pkg-install closes without a keypress when sudo validation is interrupted"
pass "pkg-install closes without a keypress when sudo validation is interrupted"

# A successful yay run reports done and refreshes the file database.
call_log="$TMPDIR/aur-calls-success"
YAY_RESULT=0 run_pkg_aur_install || fail "pkg-aur-install exits clean on successful install"
grep -q '^done$' "$call_log" || fail "pkg-aur-install reports done on successful install"
pass "pkg-aur-install reports done on successful install"
grep -q '^updatedb$' "$call_log" || fail "pkg-aur-install refreshes file database on success"
pass "pkg-aur-install refreshes file database on success"

# An aborted yay run must skip both updatedb and the done notification.
call_log="$TMPDIR/aur-calls-abort"
if YAY_RESULT=130 run_pkg_aur_install; then
  fail "pkg-aur-install exits non-zero on aborted install"
fi
{ grep -q '^updatedb$' "$call_log" || grep -q '^done$' "$call_log"; } &&
  fail "pkg-aur-install skips done and updatedb on aborted install"
pass "pkg-aur-install skips done and updatedb on aborted install"
grep -q '^error$' "$call_log" || fail "pkg-aur-install holds the terminal open on a failed install"
pass "pkg-aur-install holds the terminal open on a failed install"

# The same initial sudo validation interrupt must stop the AUR flow before yay.
call_log="$TMPDIR/aur-calls-sudo-abort"
if SUDO_VALIDATE_RESULT=130 run_pkg_aur_install; then
  fail "pkg-aur-install exits non-zero when sudo validation is interrupted"
fi
grep -q '^yay ' "$call_log" && fail "pkg-aur-install skips the yay transaction when sudo validation is interrupted"
grep -q '^done$' "$call_log" && fail "pkg-aur-install does not report done when sudo validation is interrupted"
pass "pkg-aur-install aborts before the transaction when sudo validation is interrupted"
grep -q '^error$' "$call_log" && fail "pkg-aur-install closes without a keypress when sudo validation is interrupted"
pass "pkg-aur-install closes without a keypress when sudo validation is interrupted"
