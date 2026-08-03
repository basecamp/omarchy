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
  -v|-n) exit 0 ;;
esac
exec "$@"
STUB

cat >"$stub_bin/fzf" <<'STUB'
#!/bin/bash
echo testpkg
STUB

cat >"$stub_bin/omarchy-show-done" <<'STUB'
#!/bin/bash
echo done >>"${DONE_LOG:?}"
STUB

cat >"$stub_bin/updatedb" <<'STUB'
#!/bin/bash
echo updatedb >>"${DONE_LOG:?}"
STUB

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
if [[ $1 == "-Slq" ]]; then
  echo testpkg
  exit 0
fi
exit "${PACMAN_RESULT:-0}"
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
if [[ $1 == "-Slqa" ]]; then
  echo testpkg
  exit 0
fi
exit "${YAY_RESULT:-0}"
STUB

chmod +x "$stub_bin"/*

run_pkg_install() {
  DONE_LOG="$done_log" PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$TMPDIR/home" \
    bash "$ROOT/bin/omarchy-pkg-install" >/dev/null 2>&1
}

run_pkg_aur_install() {
  DONE_LOG="$done_log" PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$TMPDIR/home" \
    bash "$ROOT/bin/omarchy-pkg-aur-install" >/dev/null 2>&1
}

mkdir -p "$TMPDIR/home"

# A successful pacman run still reports done.
done_log="$TMPDIR/done-success"
PACMAN_RESULT=0 run_pkg_install || fail "pkg-install exits clean on successful install"
grep -q done "$done_log" || fail "pkg-install reports done on successful install"
pass "pkg-install reports done on successful install"

# An aborted or failed pacman run (Ctrl+C at the sudo prompt, declined auth,
# package error) must not report done and must exit non-zero.
done_log="$TMPDIR/done-abort"
if PACMAN_RESULT=130 run_pkg_install; then
  fail "pkg-install exits non-zero on aborted install"
fi
[[ ! -e $done_log ]] || fail "pkg-install does not report done on aborted install"
pass "pkg-install does not report done on aborted install"

# A successful yay run reports done and refreshes the file database.
done_log="$TMPDIR/aur-done-success"
YAY_RESULT=0 run_pkg_aur_install || fail "pkg-aur-install exits clean on successful install"
grep -q done "$done_log" || fail "pkg-aur-install reports done on successful install"
pass "pkg-aur-install reports done on successful install"
grep -q updatedb "$done_log" || fail "pkg-aur-install refreshes file database on success"
pass "pkg-aur-install refreshes file database on success"

# An aborted yay run must skip both updatedb and the done notification.
done_log="$TMPDIR/aur-done-abort"
if YAY_RESULT=130 run_pkg_aur_install; then
  fail "pkg-aur-install exits non-zero on aborted install"
fi
[[ ! -e $done_log ]] || fail "pkg-aur-install skips done and updatedb on aborted install"
pass "pkg-aur-install skips done and updatedb on aborted install"
