#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# pgrep/killall act on real system processes, so shadow them with stubs
# controlled entirely by env vars instead of depending on which terminal
# emulators happen to be running on the machine the suite executes on.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
case "$2" in
  kitty) [[ ${OMARCHY_TEST_KITTY_RUNNING:-0} == 1 ]] ;;
  ghostty) [[ ${OMARCHY_TEST_GHOSTTY_RUNNING:-0} == 1 ]] ;;
  foot) [[ ${OMARCHY_TEST_FOOT_RUNNING:-0} == 1 ]] ;;
  *) exit 1 ;;
esac
SH

cat >"$stub_bin/killall" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$test_tmp/killall.log"
SH

chmod +x "$stub_bin/pgrep" "$stub_bin/killall"

home="$test_tmp/home"
alacritty_toml="$home/.config/alacritty/alacritty.toml"
mkdir -p "$(dirname "$alacritty_toml")"
printf 'stale\n' >"$alacritty_toml"
touch -d "1 hour ago" "$alacritty_toml"

run_restart_terminal() {
  PATH="$stub_bin:$PATH" HOME="$home" "$ROOT/bin/omarchy-restart-terminal"
}

: >"$test_tmp/killall.log"
OMARCHY_TEST_KITTY_RUNNING=0 OMARCHY_TEST_GHOSTTY_RUNNING=0 OMARCHY_TEST_FOOT_RUNNING=0 \
  run_restart_terminal >"$test_tmp/out.log" 2>"$test_tmp/err.log" || fail "no running emulators: exits cleanly"

[[ $(stat -c %Y "$alacritty_toml") -gt $(date -d '1 hour ago' +%s) ]] ||
  fail "an existing alacritty.toml is touched to trigger its live-reload watch"
pass "an existing alacritty.toml is touched to trigger its live-reload watch"

[[ ! -s $test_tmp/killall.log ]] || fail "no killall calls when kitty/ghostty are not running" "$(<"$test_tmp/killall.log")"
[[ ! -s $test_tmp/err.log ]] || fail "no foot message when foot is not running" "$(<"$test_tmp/err.log")"
pass "nothing runs for terminals that are not open"

rm -f "$alacritty_toml"
OMARCHY_TEST_KITTY_RUNNING=0 OMARCHY_TEST_GHOSTTY_RUNNING=0 OMARCHY_TEST_FOOT_RUNNING=0 \
  run_restart_terminal >/dev/null 2>&1 || fail "a missing alacritty.toml does not fail the script"
pass "a missing alacritty.toml does not fail the script"

: >"$test_tmp/killall.log"
OMARCHY_TEST_KITTY_RUNNING=1 OMARCHY_TEST_GHOSTTY_RUNNING=0 OMARCHY_TEST_FOOT_RUNNING=0 \
  run_restart_terminal >/dev/null 2>"$test_tmp/err.log" || fail "a running kitty does not fail the script"
[[ $(<"$test_tmp/killall.log") == "-SIGUSR1 kitty" ]] || fail "a running kitty is sent SIGUSR1 to reload" "$(<"$test_tmp/killall.log")"
pass "a running kitty is sent SIGUSR1 to reload"

: >"$test_tmp/killall.log"
OMARCHY_TEST_KITTY_RUNNING=0 OMARCHY_TEST_GHOSTTY_RUNNING=1 OMARCHY_TEST_FOOT_RUNNING=0 \
  run_restart_terminal >/dev/null 2>"$test_tmp/err.log" || fail "a running ghostty does not fail the script"
[[ $(<"$test_tmp/killall.log") == "-SIGUSR2 ghostty" ]] || fail "a running ghostty is sent SIGUSR2 to reload" "$(<"$test_tmp/killall.log")"
pass "a running ghostty is sent SIGUSR2 to reload"

: >"$test_tmp/killall.log"
OMARCHY_TEST_KITTY_RUNNING=0 OMARCHY_TEST_GHOSTTY_RUNNING=0 OMARCHY_TEST_FOOT_RUNNING=1 \
  run_restart_terminal >/dev/null 2>"$test_tmp/err.log" || fail "a running foot does not fail the script"
[[ ! -s $test_tmp/killall.log ]] || fail "foot is never sent a signal, since it has none to reload with" "$(<"$test_tmp/killall.log")"
grep -qF "foot cannot reload foot.ini" "$test_tmp/err.log" ||
  fail "a directly-invoked restart on a running foot gets an explicit no-reload message instead of a silent no-op" "$(<"$test_tmp/err.log")"
pass "a directly-invoked restart on a running foot gets an explicit no-reload message instead of a silent no-op"

# A theme switch only ever changes colors, which omarchy-theme-set-foot
# already applies live over OSC -- foot needs no restart for that, so
# omarchy-theme-set marks the run and the warning should stay quiet.
: >"$test_tmp/killall.log"
OMARCHY_THEME_SWITCHING=1 OMARCHY_TEST_KITTY_RUNNING=0 OMARCHY_TEST_GHOSTTY_RUNNING=0 OMARCHY_TEST_FOOT_RUNNING=1 \
  run_restart_terminal >/dev/null 2>"$test_tmp/err.log" || fail "a running foot does not fail the script during a theme switch"
[[ ! -s $test_tmp/err.log ]] ||
  fail "the foot warning is skipped during a theme switch, since colors already updated live" "$(<"$test_tmp/err.log")"
pass "the foot warning is skipped during a theme switch, since colors already updated live"
