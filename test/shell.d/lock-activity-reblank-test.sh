#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The compositor part of this file is skipped on headless machines, so pin
// the activity monitor's wiring here too: enabled only while locked, real
// input only (inhibitors do not count as idle), and every resume re-arms
// the blank.
assert(
  /IdleMonitor \{[\s\S]*?id: activityMonitor[\s\S]*?enabled: root\.lockRequested[\s\S]*?respectInhibitors: false[\s\S]*?onIsIdleChanged: if \(!isIdle\) root\.handleActivityResumed\(\)/.test(serviceQml),
  'the activity monitor is enabled while locked, ignores inhibitors, and re-arms the blank on every resume'
)

assert(
  /Process \{\s*id: blankProcess[\s\S]*?onStarted: root\.logEvent\("blank-started"\)/.test(serviceQml),
  'the blank process logs its own start'
)
JS

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_compositor "lock activity reblank test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping lock activity reblank test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
blank_marker="$TMPDIR/blank-called"
config_dir="$TMPDIR/lock-activity-reblank"
fake_bin="$TMPDIR/bin"
mkdir -p "$config_dir" "$TMPDIR/home" "$fake_bin"
cp "$SHELL_TEST_DIR/fixtures/lock-activity-reblank/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

# The fixture drives the real lock service, so a fired blank timer spawns the
# real brightness commands. Shadow them: the test wants to know the spawn
# reached the command, not to actually blank the developer's display.
cat >"$fake_bin/omarchy-brightness-display" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$blank_marker"
SH
chmod +x "$fake_bin/omarchy-brightness-display"

cat >"$fake_bin/omarchy-brightness-keyboard" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$fake_bin/omarchy-brightness-keyboard"

cat >"$fake_bin/omarchy-system-wake" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$fake_bin/omarchy-system-wake"

# The fixture never locks a real session (it sets lockRequested directly
# instead of calling beginLock()/queueSessionLock()), so this only needs to
# answer "not locked" to keep the stranded-lock check from trying to recover
# anything.
cat >"$fake_bin/omarchy-hyprland-session-locked" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$fake_bin/omarchy-hyprland-session-locked"

# lock/Service.qml spawns every Process through "bash", "-c" (not a login
# shell), so a shell.rc PATH override cannot reach it -- but a machine
# dev-linked to another checkout can still shadow the fake bin earlier in
# $PATH itself. Refuse to run the real blank against the developer's display
# unless the same lookup a plain "bash -c" would do resolves to the fake.
resolved=$(HOME="$TMPDIR/home" PATH="$fake_bin:$ROOT/bin:$PATH" bash -c 'command -v omarchy-brightness-display' 2>/dev/null || true)
if [[ $resolved != "$fake_bin/omarchy-brightness-display" ]]; then
  pass "PATH resolves omarchy-brightness-display to ${resolved:-nothing}; skipping lock activity reblank test"
  exit 0
fi

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$fake_bin:$ROOT/bin:$PATH" \
  timeout 40 quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

# The fixture's own poll for the re-armed blank firing runs up to ~20s (real
# input in a live session can keep re-arming the countdown), so give this
# outer wait enough room past that plus load/startup time.
for _ in {1..350}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "lock activity reblank quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "lock activity reblank test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Lock activity reblank result:\n' >&2
  jq . "$result" >&2
  printf 'Lock activity reblank log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "lock screen re-arms its blank from raw input while locked"
fi

# The re-armed timer is the only one allowed to reach the blank command in
# this run; the marker proves the spawn went all the way through.
for _ in {1..30}; do
  [[ -e $blank_marker ]] && break
  sleep 0.1
done
[[ -e $blank_marker ]] || {
  sed -n '1,220p' "$log" >&2
  fail "the re-armed blank timer runs omarchy-brightness-display"
}

pass "lock screen re-arms its blank from raw input while locked"
