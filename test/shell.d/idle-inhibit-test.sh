#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

state_file="$test_tmp/.local/state/omarchy/idle-inhibitors"

# The idle-inhibit daemon writes its state as JSON with a count and a detail list.
# omarchy-debug-idle reads that file and renders the D-Bus inhibitors section.
run_debug_idle() {
  HOME="$test_tmp" "$ROOT/bin/omarchy-debug-idle" 2>/dev/null \
    | sed -n '/^== D-Bus idle inhibitors ==$/,/^== .* ==$/p'
}

# No state file yet: the section reports "none".
[[ ! -f $state_file ]] || fail "no state file should exist yet"
output="$(run_debug_idle)"
[[ $output == *"none"* ]] || fail "missing state file reports none" "$output"
pass "missing state file reports none"

# Empty inhibitor list: still "none".
mkdir -p "$(dirname "$state_file")"
printf '%s' '{"count":0,"inhibitors":[]}' > "$state_file"
output="$(run_debug_idle)"
[[ $output == *"none"* ]] || fail "empty inhibitor list reports none" "$output"
pass "empty inhibitor list reports none"

# Active inhibitors: section shows the count and each app/reason.
printf '%s' '{"count":2,"inhibitors":[{"app":"Zen Browser","reason":"Playing video","cookie":1},{"app":"VLC","reason":"Playing audio","cookie":2}]}' > "$state_file"
output="$(run_debug_idle)"
[[ $output == *"active count: 2"* ]] || fail "active count is shown" "$output"
[[ $output == *"Zen Browser: Playing video (cookie 1)"* ]] || fail "first inhibitor is rendered" "$output"
[[ $output == *"VLC: Playing audio (cookie 2)"* ]] || fail "second inhibitor is rendered" "$output"
pass "active inhibitors are rendered with app, reason, and cookie"

# The daemon binary is syntactically valid and declares its command metadata.
python3 -c "import ast; ast.parse(open('$ROOT/bin/omarchy-idle-inhibit').read())" \
  || fail "idle-inhibit daemon is valid python"
grep -q "omarchy:summary=" "$ROOT/bin/omarchy-idle-inhibit" \
  || fail "idle-inhibit daemon declares a summary"
grep -q "omarchy:hidden=true" "$ROOT/bin/omarchy-idle-inhibit" \
  || fail "idle-inhibit daemon is hidden from listings"
pass "idle-inhibit daemon is valid and declares its metadata"

# The daemon's primary contract is a D-Bus service: it must own
# org.freedesktop.ScreenSaver, answer Inhibit/UnInhibit, persist the state file,
# and release inhibitors when their caller disconnects. Exercise that over a
# private bus so we don't touch the real session bus.
require_command dbus-run-session
require_command gdbus

daemon_state="$test_tmp/daemon/idle-inhibitors"
daemon_log="$test_tmp/daemon.log"
mkdir -p "$(dirname "$daemon_state")"

# A client that Inhibits and holds the connection open until killed.
cat >"$test_tmp/inhibit-hold.py" <<PY
import dbus, dbus.service, dbus.mainloop.glib, time
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
proxy = bus.get_object("org.freedesktop.ScreenSaver", "/ScreenSaver")
iface = dbus.Interface(proxy, "org.freedesktop.ScreenSaver")
print(iface.Inhibit("Zen Browser", "Playing video"), flush=True)
time.sleep(30)
PY

# A client that Inhibits then exits without UnInhibit (simulates a crash).
cat >"$test_tmp/inhibit-crash.py" <<PY
import dbus, dbus.service, dbus.mainloop.glib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
proxy = bus.get_object("org.freedesktop.ScreenSaver", "/ScreenSaver")
iface = dbus.Interface(proxy, "org.freedesktop.ScreenSaver")
print(iface.Inhibit("brief-app", "momentary"), flush=True)
PY

# Run a scenario on a private bus and report the daemon's final state count.
# The count is echoed while the daemon is still alive, before the bus tears down
# (which kills the daemon and triggers its shutdown clear-to-zero).
scenario() {
  local script="$1"
  dbus-run-session -- bash -c "
    # dbus-run-session tears the bus down when the foreground bash exits, but
    # background children are not reaped with it. SIGKILL them (not SIGTERM: the
    # daemon's SIGTERM handler would asynchronously write zero to the shared
    # state file and race a later scenario) and wait so a scenario cannot leak
    # a daemon or holding client into the test suite.
    trap 'kill -9 \$(jobs -p) 2>/dev/null || true; wait 2>/dev/null || true' EXIT
    python3 '$ROOT/bin/omarchy-idle-inhibit' --state-file '$daemon_state' >>'$daemon_log' 2>&1 &
    echo \$! >'$test_tmp/daemon.pid'
    sleep 1
    $script
    sleep 1
    cat '$daemon_state'
  " 2>/dev/null | jq -r '.count // 0'
}

# The daemon starts with zero inhibitors.
[[ $(scenario "true") == "0" ]] || fail "daemon starts with zero inhibitors"
pass "daemon starts with zero inhibitors"

# A holding client Inhibits; the count is 1 while the connection lives.
hold=$(scenario "
  python3 '$test_tmp/inhibit-hold.py' >'$test_tmp/cookie.txt' 2>&1 &
  echo \$! >'$test_tmp/hold.pid'
  sleep 1
")
[[ $(cat "$test_tmp/cookie.txt") == "1" ]] || fail "Inhibit returns a cookie" "cookie=$(cat "$test_tmp/cookie.txt")"
[[ $hold == "1" ]] || fail "daemon persists an active inhibitor" "count=$hold"
pass "daemon persists an active inhibitor"

# UnInhibit clears the inhibitor.
clear=$(scenario "
  python3 '$test_tmp/inhibit-hold.py' >'$test_tmp/cookie.txt' 2>&1 &
  echo \$! >'$test_tmp/hold.pid'
  sleep 1
  gdbus call --session --dest org.freedesktop.ScreenSaver --object-path /ScreenSaver \\
    --method org.freedesktop.ScreenSaver.UnInhibit \$(cat '$test_tmp/cookie.txt') >/dev/null
  sleep 1
")
[[ $clear == "0" ]] || fail "UnInhibit clears the inhibitor" "count=$clear"
pass "UnInhibit clears the inhibitor"

# A caller that Inhibits then crashes leaves no stale inhibitor behind.
crashed=$(scenario "
  python3 '$test_tmp/inhibit-crash.py' >'$test_tmp/cookie.txt' 2>&1 &
  echo \$! >'$test_tmp/crash.pid'
  sleep 1
  kill -9 \$(cat '$test_tmp/crash.pid') 2>/dev/null
  sleep 1
")
[[ $crashed == "0" ]] || fail "disconnecting caller releases its inhibitor" "count=$crashed"
pass "disconnecting caller releases its inhibitor"
