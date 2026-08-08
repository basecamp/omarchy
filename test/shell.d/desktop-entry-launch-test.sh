#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
exit "${OMARCHY_TEST_PKG_STATUS:-0}"
SH

for command in omarchy-pkg-aur-add omarchy-install-emacs omazed omarchy-theme-set-vscode omarchy-install-gaming-gpu-lib32; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
exit 0
SH
done

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$OMARCHY_TEST_PRESENTATION"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export OMARCHY_TEST_LOG="$test_tmp/launch.log"
export OMARCHY_TEST_PRESENTATION="$test_tmp/presentation"
export PATH="$mock_bin:$PATH"

wait_for_launch() {
  local expected="$1"

  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fxq "$expected" "$OMARCHY_TEST_LOG" && return 0
    sleep 0.01
  done

  return 1
}

assert_detached_installer_launch() {
  local script="$1"
  local desktop_id="$2"

  : >"$OMARCHY_TEST_LOG"
  bash "$ROOT/bin/$script"

  wait_for_launch "launch:uwsm-app -- gtk-launch $desktop_id" ||
    fail "$script launches its desktop entry through gtk-launch in a UWSM scope"
  grep -Fqx "setsid uwsm-app -- gtk-launch $desktop_id >/dev/null 2>&1 &" "$ROOT/bin/$script" ||
    fail "$script detaches its scoped desktop-entry launch"
  pass "$script detaches its scoped desktop-entry launch"
}

assert_detached_installer_launch omarchy-install-editor-emacs emacsclient
assert_detached_installer_launch omarchy-install-editor-vscode code
assert_detached_installer_launch omarchy-install-editor-zed dev.zed.Zed
assert_detached_installer_launch omarchy-install-gaming-heroic heroic
assert_detached_installer_launch omarchy-install-gaming-steam steam

bash "$ROOT/bin/omarchy-install-and-launch" "Example App" "alpha beta" "Disk Usage"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")

[[ $presentation_command == *'echo Installing\ Example\ App...;'* ]] ||
  fail "generic installer shell-quotes the display name" "$presentation_command"
[[ $presentation_command == *'omarchy-pkg-add alpha beta && (setsid uwsm-app -- gtk-launch Disk\ Usage >/dev/null 2>&1 &)'* ]] ||
  fail "generic installer waits for packages and detaches only the scoped launch" "$presentation_command"
pass "generic installer waits for packages and detaches only the scoped launch"

: >"$OMARCHY_TEST_LOG"
bash -c "$presentation_command"
grep -Fxq 'pkg:alpha beta' "$OMARCHY_TEST_LOG" ||
  fail "generic installer passes every package to the package helper"
wait_for_launch 'launch:uwsm-app -- gtk-launch Disk Usage' ||
  fail "generic installer preserves a desktop ID containing spaces"
pass "generic installer preserves a desktop ID containing spaces"

: >"$OMARCHY_TEST_LOG"
if OMARCHY_TEST_PKG_STATUS=1 bash -c "$presentation_command"; then
  fail "generic installer propagates package installation failure"
fi
if grep -q '^launch:' "$OMARCHY_TEST_LOG"; then
  fail "generic installer does not launch after package installation failure"
fi
pass "generic installer does not launch after package installation failure"
