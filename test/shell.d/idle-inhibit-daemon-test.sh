#!/bin/bash

# Drives bin/omarchy-idle-inhibit-daemon over a real private session bus
# (dbus-run-session) and asserts the org.freedesktop.ScreenSaver contract the
# browsers rely on: both object paths, cookie stacking, disconnect reaping,
# tolerant uninhibit, and an atomically published state file.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command busctl
require_command dbus-run-session
require_command python3

daemon="$ROOT/bin/omarchy-idle-inhibit-daemon"
[[ -x $daemon ]] || fail "omarchy-idle-inhibit-daemon exists and is executable"

session_dir=$(mktemp -d)
trap 'rm -rf "$session_dir"' EXIT

runtime_dir="$session_dir/runtime"
mkdir -p "$runtime_dir"

inner="$session_dir/inner.sh"
PROBE="$ROOT/bin/omarchy-idle-inhibit-probe"

cat >"$inner" <<'INNER'
#!/bin/bash
set -euo pipefail

runtime_dir="$1"
export XDG_RUNTIME_DIR="$runtime_dir"
state_dir="$runtime_dir/omarchy/idle-inhibit"
state_file="$state_dir/state"

fail() {
  echo "not ok - $1 ${2:-}" >&2
  exit 1
}
pass() {
  echo "ok - $1"
}

wait_for() {
  local description="$1" deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    "${@:2}" && return 0
    sleep 0.1
  done
  fail "$description (timed out)"
}

name_owned() {
  busctl --user --no-pager status "${1:?}" >/dev/null 2>&1
}

state_json() {
  cat "$state_file" 2>/dev/null || printf ''
}

inhibited() {
  jq -e '.inhibited == true and (.holders | length > 0)' "$state_file" >/dev/null 2>&1
}

not_inhibited() {
  jq -e '.inhibited == false and .count == 0 and (.holders | length == 0)' "$state_file" >/dev/null 2>&1
}

holders_are() {
  jq -e --argjson n "$1" '(.holders | length) == $n and .count == $n and .inhibited == ($n > 0)' \
    "$state_file" >/dev/null 2>&1
}

without_app() {
  jq -e --arg app "$1" '(.holders | map(.app) | index($app)) == null' "$state_file" >/dev/null 2>&1
}

free_name() {
  ! name_owned "${1:?}"
}

inhibit() {
  # app reason path
  busctl --user --no-pager call org.freedesktop.ScreenSaver "$3" \
    org.freedesktop.ScreenSaver Inhibit ss "$1" "$2" 2>/dev/null |
    awk '/^u / { print $2; exit }'
}

uninhibit() {
  busctl --user --no-pager call org.freedesktop.ScreenSaver "${2:?}" \
    org.freedesktop.ScreenSaver UnInhibit u "${1:?}" >/dev/null 2>&1
}

SS_NEW=/org/freedesktop/ScreenSaver
SS_LEGACY=/ScreenSaver
PM=/org/freedesktop/PowerManagement/Inhibit

daemon_pid=

start_daemon() {
  set +m
  "$DAEMON" &
  daemon_pid=$!
  disown "$daemon_pid" 2>/dev/null || true
}

stop_daemon() {
  [[ -n $daemon_pid ]] && kill "$daemon_pid" 2>/dev/null || true
  wait "$daemon_pid" 2>/dev/null || true
  daemon_pid=
}
trap stop_daemon EXIT

# --- startup ---------------------------------------------------------------

start_daemon
wait_for "daemon owns org.freedesktop.ScreenSaver" name_owned org.freedesktop.ScreenSaver
pass "daemon owns org.freedesktop.ScreenSaver"

wait_for "daemon owns org.freedesktop.PowerManagement" name_owned org.freedesktop.PowerManagement
pass "daemon owns org.freedesktop.PowerManagement"

# The nothing-inhibited snapshot exists before any caller, so a consumer that
# starts after the daemon never guesses its initial state.
wait_for "initial state snapshot published" test -s "$state_file"
not_inhibited || fail "initial state reports nothing inhibited" "$(state_json)"
pass "initial state snapshot reports nothing inhibited"

mode=$(stat -c '%a' "$state_file" 2>/dev/null || stat -f '%Lp' "$state_file")
[[ $mode == "600" ]] || fail "state file is owner-only readable" "mode: $mode"
pass "state file is owner-only readable"

# --- Raw contract on both object paths --------------------------------------
#
# Chromium calls /org/freedesktop/ScreenSaver; VLC and Firefox call the legacy
# /ScreenSaver path. Each busctl call is transient (the spec releases its
# inhibit when the caller disconnects), so these assert the reply only — held
# state is the live-connection section below.

c=$(inhibit "path.probe.new" "probe" "$SS_NEW")
[[ $c =~ ^[0-9]+$ ]] || fail "Inhibit answers on /org/freedesktop/ScreenSaver (Chromium path)" "$c"
pass "Inhibit answers on /org/freedesktop/ScreenSaver (Chromium path)"

c=$(inhibit "path.probe.legacy" "probe" "$SS_LEGACY")
[[ $c =~ ^[0-9]+$ ]] || fail "Inhibit answers on /ScreenSaver (VLC/Firefox legacy path)" "$c"
pass "Inhibit answers on /ScreenSaver (VLC/Firefox legacy path)"

# --- Held inhibits from one live connection ---------------------------------
#
# busctl is a transient bus connection: it exits with its call, and the spec
# ends an inhibition when its client disconnects — so every busctl inhibit is
# reaped almost immediately. Assertions about *held* state therefore come from
# one python client that keeps its connection open; the busctl calls above
# prove the raw per-path contract only.

holder="$runtime_dir/holder.out"
python3 - >"$holder" <<'PY' &
import os, sys, time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

def inhibit(path, iface, app, reason):
    return bus.call_sync(
        "org.freedesktop.ScreenSaver", path, iface, "Inhibit",
        GLib.Variant("(ss)", (app, reason)), GLib.VariantType("(u)"),
        Gio.DBusCallFlags.NONE, -1, None).unpack()[0]

c1 = inhibit("/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver",
             "org.chromium.chromium", "Video Wake Lock")
c2 = inhibit("/ScreenSaver", "org.freedesktop.ScreenSaver",
             "org.videolan.vlc", "Playing media")
c3 = inhibit("/org/freedesktop/PowerManagement/Inhibit",
             "org.freedesktop.PowerManagement.Inhibit",
             "org.chromium.chromium", "Playing audio")
print(f"{c1} {c2} {c3}", flush=True)
time.sleep(600)
PY
holder_pid=$!
wait_for "holder published its cookies" test -s "$holder"
read -r cookie_chromium cookie_vlc cookie_pm <"$holder"

wait_for "held inhibits stack in the state file" holders_are 3
pass "concurrent inhibits from Chromium, VLC, and PowerManagement stack"

jq -e '([.holders[].app] | sort) == (["org.chromium.chromium", "org.chromium.chromium", "org.videolan.vlc"] | sort)' \
  "$state_file" >/dev/null || fail "state names each inhibiting application" "$(state_json)"
pass "state names each inhibiting application"

jq -e --arg owner "$holder_pid" 'all(.holders[]; (.owner | startswith(":1.")))' \
  "$state_file" >/dev/null || fail "holders record the owning bus name" "$(state_json)"
pass "holders record the owning bus name"

active=$(busctl --user --no-pager call org.freedesktop.ScreenSaver "$SS_NEW" \
  org.freedesktop.ScreenSaver GetActive 2>&1 || true)
grep -q "GetActive" <<<"$active" && grep -qi "no such method\|unknown method\|unknownmethod" <<<"$active" ||
  fail "GetActive is not offered: reporting screensaver activation it does not own would be backwards" "$active"
pass "the KDE-legacy GetActive is deliberately absent"

# ... and no ActiveChanged signal may fire either: emitting the KDE semantics
# ("screensaver blanked") from inhibit-held state would be exactly backwards.
signal_absent=$(python3 - <<'PY'
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
seen = []
loop = GLib.MainLoop()

def on_signal(conn, sender, path, iface, signal, params):
    seen.append(signal)

bus.signal_subscribe("org.freedesktop.ScreenSaver", "org.freedesktop.ScreenSaver",
                     "ActiveChanged", None, None, Gio.DBusSignalFlags.NONE, on_signal)

res = bus.call_sync("org.freedesktop.ScreenSaver", "/ScreenSaver",
                    "org.freedesktop.ScreenSaver", "Inhibit",
                    GLib.Variant("(ss)", ("nosignal.client", "probe")),
                    GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
cookie = res.unpack()[0]
bus.call_sync("org.freedesktop.ScreenSaver", "/ScreenSaver",
              "org.freedesktop.ScreenSaver", "UnInhibit",
              GLib.Variant("(u)", (cookie,)), None,
              Gio.DBusCallFlags.NONE, -1, None)
GLib.timeout_add(300, loop.quit)
loop.run()
print("ActiveChanged" not in seen)
PY
)
[[ $signal_absent == "True" ]] || fail "no ActiveChanged fires for inhibit transitions"
pass "no ActiveChanged fires for inhibit transitions"

has=$(busctl --user --no-pager call org.freedesktop.PowerManagement "$PM" \
  org.freedesktop.PowerManagement.Inhibit HasInhibit 2>/dev/null | awk '{ print $2; exit }')
[[ $has == "true" ]] || fail "HasInhibit reports held inhibits" "$has"
pass "HasInhibit agrees with the state file"

# --- UnInhibit --------------------------------------------------------------

# Released from a different connection than the one that inhibited (busctl):
# sender identity is not verified, matching hypridle — any same-uid process
# can already run code.
uninhibit "$cookie_vlc" "$SS_NEW"
wait_for "uninhibit releases one holder and its app leaves the state" holders_are 2
wait_for "uninhibit releases the vlc holder" without_app org.videolan.vlc
pass "UnInhibit releases a held inhibit"

# An unknown cookie is tolerated, not an error: a restarted browser replaying
# a stale cookie must not wedge or error the session.
unknown=$((cookie_chromium + 1000000))
uninhibit "$unknown" "$SS_NEW"
wait_for "unknown uninhibit changed nothing" holders_are 2
pass "UnInhibit with an unknown cookie returns normally"

# --- Disconnect reaping ------------------------------------------------------

# Killing the holder drops its bus connection: every cookie it still held must
# go with it, which is what keeps a crashed browser from pinning the session
# awake forever.
kill "$holder_pid" 2>/dev/null || true
wait_for "a crashed client's inhibits are reaped" not_inhibited
pass "inhibits are reaped when their client leaves the bus"

# --- HasInhibitChanged is the one transition signal that survives ------------

# (ActiveChanged was dropped above: it belongs to "screensaver blanked"
# semantics the daemon cannot honestly report. HasInhibitChanged has unambiguous
# inhibit semantics, and Clight-class clients listen for it.)

signal_seen=$(python3 - <<'PY'
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
seen = []
loop = GLib.MainLoop()

def on_signal(conn, sender, path, iface, signal, params):
    seen.append(params.unpack()[0])
    if len(seen) == 1:
        loop.quit()

bus.signal_subscribe("org.freedesktop.PowerManagement", "org.freedesktop.PowerManagement.Inhibit",
                     "HasInhibitChanged", None, None, Gio.DBusSignalFlags.NONE, on_signal)

res = bus.call_sync("org.freedesktop.ScreenSaver", "/ScreenSaver",
                    "org.freedesktop.ScreenSaver", "Inhibit",
                    GLib.Variant("(ss)", ("signal.client", "signal probe")),
                    GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
cookie = res.unpack()[0]
# This connection stays alive until the check below is queued, so the
# inhibit is not reaped before the signal fires.
GLib.timeout_add(1500, loop.quit)
GLib.idle_add(lambda: bus.call_sync("org.freedesktop.ScreenSaver", "/ScreenSaver",
                                    "org.freedesktop.ScreenSaver", "UnInhibit",
                                    GLib.Variant("(u)", (cookie,)), None,
                                    Gio.DBusCallFlags.NONE, -1, None) and False)
loop.run()
print(len(seen) >= 1 and seen[0] is True)
PY
)
[[ $signal_seen == "True" ]] || fail "HasInhibitChanged fires on transitions"
pass "HasInhibitChanged fires on transitions"

wait_for "state settles after the signal probe" not_inhibited

# --- Atomic publication under churn ------------------------------------------

storm_ok=1
for i in {1..30}; do
  c=$(inhibit "storm.client" "churn $i" "$SS_NEW" || true)
  jq -e . "$state_file" >/dev/null 2>&1 || { storm_ok=0; break; }
  [[ -n ${c:-} ]] && uninhibit "$c" "$SS_NEW"
  jq -e . "$state_file" >/dev/null 2>&1 || { storm_ok=0; break; }
done
(( storm_ok )) || fail "state file is always complete JSON during inhibit churn"
pass "state file stays complete JSON during inhibit churn"

# --- A second daemon never fights over the name -------------------------------

"$DAEMON" >/dev/null 2>&1
second_status=$?
(( second_status == 0 )) || fail "a daemon that cannot own the name exits 0 (got $second_status)"
name_owned org.freedesktop.ScreenSaver || fail "the first daemon keeps the name"
pass "a second daemon exits quietly and the first keeps the name"

wait_for "state settles after the duplicate start" not_inhibited

# --- A dead daemon's last write reads as released -----------------------------
#
# A SIGKILL leaves no orderly final publish — whatever the file claimed while
# serving stays on disk. Every snapshot therefore carries the serving pid, and
# the probe emits one empty line for a file whose pid is gone, so a crashed
# daemon cannot pin the idle timers off; no bystander cleanup or coordination
# is involved. The holder stays connected so the last write still claims it.

python3 - >"$runtime_dir/kill-holder.out" <<'PY' &
import time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
res = bus.call_sync(
    "org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver",
    "Inhibit", GLib.Variant("(ss)", ("kill.client", "hold across sigkill")),
    GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
print(res.unpack()[0], flush=True)
time.sleep(600)
PY
kill_holder_pid=$!
wait_for "the kill-test holder is visible" inhibited

killed_pid=$daemon_pid
kill -KILL "$daemon_pid"
deadline=$((SECONDS + 10))
while ((SECONDS < deadline)) && kill -0 "$daemon_pid" 2>/dev/null; do sleep 0.1; done
if kill -0 "$daemon_pid" 2>/dev/null; then fail "the daemon dies on SIGKILL"; fi
wait "$daemon_pid" 2>/dev/null || true
daemon_pid=

jq -e '.inhibited == true and (.holders | length > 0)' "$state_file" >/dev/null ||
  fail "SIGKILL leaves the last live snapshot on disk" "$(cat "$state_file")"
jq -e --argjson pid "$killed_pid" '.pid == $pid' "$state_file" >/dev/null ||
  fail "SIGKILL snapshot still names the dead serving pid" "$(cat "$state_file")"
if kill -0 "$killed_pid" 2>/dev/null; then fail "the killed daemon's pid is really gone"; fi

out=$("$PROBE" "$state_file" ; printf 'x')
[[ $out == $'\nx' ]] || fail "the probe emits one empty line for a SIGKILL'd daemon's last write" "$(printf %q "$out")"
pass "SIGKILL mid-inhibit still reads as released"

kill "$kill_holder_pid" 2>/dev/null || true
wait "$kill_holder_pid" 2>/dev/null || true

# Missing state: one empty line.
out=$("$PROBE" "$runtime_dir/does-not-exist" ; printf 'x')
[[ $out == $'\nx' ]] || fail "a missing state file reads as nothing inhibited" "$(printf %q "$out")"
pass "a missing state file reads as nothing inhibited"

# Torn/garbage state: one empty line.
printf '%s' '{"inhibited":tru' >"$state_file"
out=$("$PROBE" "$state_file" ; printf 'x')
[[ $out == $'\nx' ]] || fail "a torn state file yields exactly one empty line" "$(printf %q "$out")"
pass "missing and torn state files read as nothing inhibited"

start_daemon
wait_for "a fresh daemon republishes over the stale file" not_inhibited

# --- An orderly stop leaves the file honest -----------------------------------
#
# systemd stops are clean: before exiting, the daemon republishes an empty
# snapshot rather than leaving whatever clients held at the moment of the
# stop on disk.

python3 - >"$runtime_dir/term-holder.out" <<'PY' &
import time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
res = bus.call_sync(
    "org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver",
    "Inhibit", GLib.Variant("(ss)", ("term.client", "hold across sigterm")),
    GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None)
print(res.unpack()[0], flush=True)
time.sleep(600)
PY
holder_term_pid=$!
wait_for "the term-test holder is visible" inhibited

kill -TERM "$daemon_pid"
deadline=$((SECONDS + 10))
while ((SECONDS < deadline)) && kill -0 "$daemon_pid" 2>/dev/null; do sleep 0.1; done
if kill -0 "$daemon_pid" 2>/dev/null; then fail "the daemon exits cleanly on SIGTERM"; fi

jq -e '.inhibited == false and .count == 0' "$state_file" >/dev/null ||
  fail "SIGTERM leaves a clean nothing-inhibited snapshot" "$(cat "$state_file")"
pass "SIGTERM leaves a clean nothing-inhibited snapshot"
kill "$holder_term_pid" 2>/dev/null || true
wait "$holder_term_pid" 2>/dev/null || true
daemon_pid=

echo "all inner assertions passed"

INNER

chmod +x "$inner"

export DAEMON="$daemon" PROBE="$PROBE"
timeout 120 dbus-run-session -- bash "$inner" "$runtime_dir" ||
  fail "omarchy-idle-inhibit-daemon passes the live session-bus contract" \
    "see the inner assertion output above"

pass "omarchy-idle-inhibit-daemon passes the live session-bus contract"
