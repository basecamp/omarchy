#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

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

require_compositor "idle lock wake test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping idle lock wake test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
wake_marker="$TMPDIR/wake-called"
config_dir="$TMPDIR/idle-lock-wake"
fake_bin="$TMPDIR/bin"
mkdir -p "$config_dir" "$TMPDIR/home" "$fake_bin"
cp "$SHELL_TEST_DIR/fixtures/idle-lock-wake/shell.qml" "$config_dir/shell.qml"

# The fixture drives the real idle service, so an unlocked cancel spawns the
# real wake command. Shadow it: the test wants to know it ran, not to wake
# the developer's display.
cat >"$fake_bin/omarchy-system-wake" <<SH
#!/bin/bash
touch "$wake_marker"
SH
chmod +x "$fake_bin/omarchy-system-wake"

# The idle service spawns its commands through a login shell, and the profile
# of a machine dev-linked to another checkout puts that checkout's bin first.
# Refuse to run the real wake against the developer's display.
resolved=$(HOME="$TMPDIR/home" PATH="$fake_bin:$ROOT/bin:$PATH" bash -lc 'command -v omarchy-system-wake' 2>/dev/null || true)
if [[ $resolved != "$fake_bin/omarchy-system-wake" ]]; then
  pass "login shell resolves omarchy-system-wake to ${resolved:-nothing}; skipping idle lock wake test"
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
  timeout 15 quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "idle lock wake quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "idle lock wake test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Idle lock wake result:\n' >&2
  jq . "$result" >&2
  printf 'Idle lock wake log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "idle service leaves a locked session's display to the lock screen"
fi

# The unlocked cancel is the only one allowed to reach the wake command, and
# the fixture ran it last; the marker proves the spawn went all the way through.
for _ in {1..30}; do
  [[ -e $wake_marker ]] && break
  sleep 0.1
done
[[ -e $wake_marker ]] || {
  sed -n '1,220p' "$log" >&2
  fail "the unlocked cancel runs omarchy-system-wake"
}

pass "idle service leaves a locked session's display to the lock screen"
