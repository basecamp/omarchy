#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_compositor "idle state persistence test"
require_command quickshell
require_command jq

test_tmp=$(mktemp -d)
test_home="$test_tmp/home with spaces"
fixture="$test_tmp/idle"
qs_pid=""
cleanup() {
  if [[ -n $qs_pid ]]; then
    kill "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT
mkdir -p "$test_home" "$fixture" "$test_tmp/bin"
cat > "$fixture/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  Loader {
    source: "file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/services/idle/Service.qml"
    onLoaded: item.shell = { shellConfig: { idle: { screensaver: 86400, lock: 86400 } } }
  }
}
QML
cat > "$test_tmp/bin/bash" <<'BASH'
#!/bin/bash
if [[ ${1:-} == "-c" && ${2:-} == *'head -c'* ]]; then
  if [[ -e $HOME/fail-read ]]; then printf 'yes:'; exit 1; fi
  if [[ -e $HOME/delay-read ]]; then
    /bin/bash "$@"
    touch "$HOME/read-finished"
    sleep 0.4
    exit 0
  fi
fi
if [[ ${1:-} == "-c" && ${2:-} == *mktemp* ]]; then
  [[ ! -e $HOME/fail-write ]] || exit 1
  [[ ! -e $HOME/delay-write ]] || sleep 0.3
fi
exec /bin/bash "$@"
BASH
cat > "$test_tmp/bin/omarchy-notification-send" <<'BASH'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/notifications"
BASH
chmod +x "$test_tmp/bin/"*
call() { quickshell ipc -p "$fixture" call idle "$@"; }
await_state() {
  local predicate="$1"
  for _ in {1..60}; do
    if call status 2>/dev/null | jq -e "$predicate" >/dev/null 2>&1; then return 0; fi
    sleep 0.05
  done
  cat "$test_tmp/shell.log" >&2
  fail "idle state reaches $predicate"
}
start_shell() {
  HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_STATE_HOME="$test_home/.local/state" \
    OMARCHY_PATH="$ROOT" PATH="$test_tmp/bin:$PATH" \
    quickshell -p "$fixture" --no-color > "$test_tmp/shell.log" 2>&1 &
  qs_pid=$!
  await_state '.stayAwakeStateLoaded == true'
}
stop_shell() {
  quickshell kill -p "$fixture" >/dev/null
  wait "$qs_pid" || true
  qs_pid=""
}
state_file="$test_home/.local/state/omarchy/indicators/stay-awake"
start_shell
await_state '.enabled == true'
call stayAwakeFor 60 >/dev/null
await_state '.stayAwakeUntil > 0'
for _ in {1..50}; do [[ -s $state_file ]] && break; sleep 0.05; done
deadline=$(cat "$state_file")
stop_shell
start_shell
await_state ".stayAwakeUntil == $deadline"
pass "timed state survives a shell restart without extending its deadline"

for invalid in 0 -1 86401; do
  [[ $(call stayAwakeFor "$invalid") == "invalid duration" ]] || fail "Invalid duration is refused"
  await_state ".stayAwakeUntil == $deadline"
done
pass "invalid requests do not change the running timer"

call stayAwakeFor 1 >/dev/null
await_state '.stayAwakeUntil > 0'
sleep 1.2
await_state '.enabled == true'
[[ -s $state_file ]] || fail "Expiry does not need to delete the deadline"
HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" status | jq -e '.enabled == false' >/dev/null
stop_shell
start_shell
await_state '.enabled == true'
pass "expiry restores idle even across restart, without a cleanup write"

for raw in '1e300' 'Infinity' 'not a deadline' $'\n' $'2000\nno'; do
  call disable >/dev/null
  await_state '.stayAwake == true'
  sleep 0.15
  printf '%s' "$raw" > "$state_file"
  sleep 0.1
  await_state '.enabled == true'
done
pass "malformed state does not disable idle"

printf 'preserve this' > "$test_home/victim"
rm "$state_file"
ln -s "$test_home/victim" "$state_file"
call stayAwakeFor 60 >/dev/null
await_state '.stayAwakeUntil > 0'
for _ in {1..50}; do [[ ! -L $state_file ]] && break; sleep 0.05; done
[[ $(cat "$test_home/victim") == "preserve this" && ! -L $state_file ]] || fail "Atomic writer must preserve symlink targets"
pass "the shell replaces state symlinks without truncating their targets"

# Force overlapping asynchronous saves. Only the newest request should remain.
touch "$test_home/delay-write"
call stayAwakeFor 60 >/dev/null
call enable >/dev/null
call disable >/dev/null
call stayAwakeFor 1800 >/dev/null
sleep 1
await_state '.stayAwakeUntil > (now * 1000 + 1700000)'
rm "$test_home/delay-write"
pass "overlapping choices preserve the latest requested duration"

# Hold a completed old read open while an external command changes the file.
call enable >/dev/null
await_state '.enabled == true'
sleep 0.2
touch "$test_home/delay-read"
: > "$state_file"
for _ in {1..50}; do [[ -e $test_home/read-finished ]] && break; sleep 0.02; done
[[ -e $test_home/read-finished ]] || fail "Delayed read starts"
rm "$state_file" "$test_home/delay-read"
sleep 0.7
await_state '.enabled == true'
pass "a file change during an in-flight probe is not lost"

# Failed reads must not turn a partial 'yes:' response into indefinite mode.
touch "$test_home/fail-read"
: > "$state_file"
sleep 0.3
await_state '.enabled == true'
rm "$test_home/fail-read" "$state_file"
pass "read errors cannot become an indefinite stay-awake session"

touch "$test_home/fail-write"
call stayAwakeFor 60 >/dev/null
sleep 0.3
await_state '.enabled == true'
[[ ! -e $state_file ]] || fail "Failed writes leave prior state intact"
[[ -s $test_home/notifications ]] || fail "Failed writes notify the user"
rm "$test_home/fail-write"
pass "failed saves preserve the prior setting and notify the user"
