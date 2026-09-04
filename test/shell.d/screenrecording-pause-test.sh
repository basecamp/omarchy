#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$PAUSED_FILE"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

# The dispatch under test hardcodes /tmp/omarchy-screenrecord-paused (matching
# the existing /tmp/omarchy-screenrecord-filename convention), so the test has
# to own that path directly rather than isolate it under $tmp_dir.
PAUSED_FILE="/tmp/omarchy-screenrecord-paused"
rm -f "$PAUSED_FILE"

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_REC_ACTIVE:-true} == "true" ]]
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_PKILL_LOG"
exit 0
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_NOTIF_ARGS"
SH

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

mkdir -p "$tmp_dir/videos"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
mkdir -p "$HOME"
export XDG_VIDEOS_DIR="$tmp_dir/videos"
export OMARCHY_TEST_PKILL_LOG="$tmp_dir/pkill.log"
export OMARCHY_TEST_NOTIF_ARGS="$tmp_dir/notif.log"
: >"$OMARCHY_TEST_PKILL_LOG"
: >"$OMARCHY_TEST_NOTIF_ARGS"

# Active recording -> pause creates the marker, sends SIGUSR2, and notifies.
OMARCHY_TEST_REC_ACTIVE=true "$ROOT/bin/omarchy-capture-screenrecording" --pause-recording
[[ -f $PAUSED_FILE ]] || fail "pause creates the paused marker file"
grep -qx -- '-SIGUSR2 -f ^gpu-screen-recorder' "$OMARCHY_TEST_PKILL_LOG" || \
  fail "pause signals SIGUSR2 to gpu-screen-recorder" "$(cat "$OMARCHY_TEST_PKILL_LOG")"
grep -Fx -- 'Recording paused' "$OMARCHY_TEST_NOTIF_ARGS" || \
  fail "pause notifies that recording paused" "$(cat "$OMARCHY_TEST_NOTIF_ARGS")"
pass "pause signals SIGUSR2, sets the marker, and notifies"

# Second toggle -> resume removes the marker and notifies.
OMARCHY_TEST_REC_ACTIVE=true "$ROOT/bin/omarchy-capture-screenrecording" --pause-recording
[[ ! -f $PAUSED_FILE ]] || fail "resume clears the paused marker file"
grep -Fx -- 'Recording resumed' "$OMARCHY_TEST_NOTIF_ARGS" || \
  fail "resume notifies that recording resumed" "$(cat "$OMARCHY_TEST_NOTIF_ARGS")"
pass "resume clears the marker and notifies"

# Toggling twice sent SIGUSR2 both times (pause then resume), never SIGINT.
[[ $(grep -c -- '-SIGUSR2' "$OMARCHY_TEST_PKILL_LOG") -eq 2 ]] || \
  fail "pause/resume only ever sends SIGUSR2" "$(cat "$OMARCHY_TEST_PKILL_LOG")"
! grep -q -- '-SIGINT' "$OMARCHY_TEST_PKILL_LOG" || \
  fail "pause/resume never sends the stop signal" "$(cat "$OMARCHY_TEST_PKILL_LOG")"
pass "pause/resume toggles only SIGUSR2"

# No active recording -> --pause-recording is a no-op that exits nonzero.
: >"$OMARCHY_TEST_PKILL_LOG"
if OMARCHY_TEST_REC_ACTIVE=false "$ROOT/bin/omarchy-capture-screenrecording" --pause-recording; then
  fail "pause with no active recording exits nonzero"
fi
[[ ! -f $PAUSED_FILE ]] || fail "pause with no active recording leaves no marker"
[[ ! -s $OMARCHY_TEST_PKILL_LOG ]] || fail "pause with no active recording sends no signal" "$(cat "$OMARCHY_TEST_PKILL_LOG")"
pass "pause with no active recording is a non-signaling no-op"
