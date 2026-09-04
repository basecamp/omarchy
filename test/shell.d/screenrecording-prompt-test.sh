#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$PAUSED_FILE" "$RECORDING_FILE"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

PAUSED_FILE="/tmp/omarchy-screenrecord-paused"
RECORDING_FILE="/tmp/omarchy-screenrecord-filename"
PGREP_STATE="$tmp_dir/pgrep-state"
PKILL_LOG="$tmp_dir/pkill.log"
SELECT_LOG="$tmp_dir/select.log"
MENU_LOG="$tmp_dir/menu.log"
NOTIF_LOG="$tmp_dir/notif.log"

rm -f "$PAUSED_FILE" "$RECORDING_FILE"
echo active >"$PGREP_STATE"

# First call returns active and flips to inactive so stop_screenrecording's wait
# loop exits without a 5s spin. Tests reset the state file per case.
cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
state=$(cat "$OMARCHY_TEST_PGREP_STATE" 2>/dev/null || echo active)
if [[ $state == active ]]; then
  echo inactive >"$OMARCHY_TEST_PGREP_STATE"
  exit 0
else
  exit 1
fi
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_PKILL_LOG"
exit 0
SH

# omarchy-menu-select returns the choice the test pinned, or exits 1 for cancel.
cat >"$stub_bin/omarchy-menu-select" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_SELECT_LOG"
if [[ ${OMARCHY_TEST_SELECT_CANCEL:-false} == "true" ]]; then exit 1; fi
printf '%s\n' "${OMARCHY_TEST_SELECT_CHOICE:-}"
SH

cat >"$stub_bin/omarchy-menu" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MENU_LOG"
exit 0
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_NOTIF_LOG"
SH

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 0
SH

# stop_screenrecording calls ffmpeg/ffprobe for finalize + preview; stub them so
# the path completes without the real binaries. ffmpeg touches .mp4 outputs so
# finalize's `mv` finds the processed file and doesn't noise up stderr.
cat >"$stub_bin/ffmpeg" <<'SH'
#!/bin/bash
for a in "$@"; do [[ $a == *.mp4 ]] && touch -- "$a"; done
exit 0
SH
cat >"$stub_bin/ffprobe" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

mkdir -p "$tmp_dir/videos"
# stop_screenrecording reads the in-progress filename from $RECORDING_FILE and
# builds a preview path from it; give it a real file so that path is valid.
fake_recording="$tmp_dir/fake-recording.mp4"
: >"$fake_recording"
echo "$fake_recording" >"$RECORDING_FILE"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
mkdir -p "$HOME"
export XDG_VIDEOS_DIR="$tmp_dir/videos"
export OMARCHY_TEST_PGREP_STATE="$PGREP_STATE"
export OMARCHY_TEST_PKILL_LOG="$PKILL_LOG"
export OMARCHY_TEST_SELECT_LOG="$SELECT_LOG"
export OMARCHY_TEST_MENU_LOG="$MENU_LOG"
export OMARCHY_TEST_NOTIF_LOG="$NOTIF_LOG"
export OMARCHY_TEST_SELECT_CANCEL=false
export OMARCHY_TEST_SELECT_CHOICE=""

run_prompt() {
  echo active >"$PGREP_STATE"
  rm -f "$PAUSED_FILE"
  : >"$PKILL_LOG"
  "$ROOT/bin/omarchy-capture-screenrecording" --prompt
}

# Pause choice -> SIGUSR2, marker set, no SIGINT.
OMARCHY_TEST_SELECT_CHOICE="Pause recording" run_prompt
[[ -f $PAUSED_FILE ]] || fail "pause choice creates the paused marker"
grep -qx -- '-SIGUSR2 -f ^gpu-screen-recorder' "$PKILL_LOG" || \
  fail "pause choice sends SIGUSR2" "$(cat "$PKILL_LOG")"
! grep -q -- '-SIGINT' "$PKILL_LOG" || fail "pause choice does not send SIGINT"
pass "pause choice pauses the capture without stopping"

# Resume choice (marker pre-set) -> SIGUSR2, marker cleared.
echo active >"$PGREP_STATE"
touch "$PAUSED_FILE"
: >"$PKILL_LOG"
OMARCHY_TEST_SELECT_CHOICE="Resume recording" "$ROOT/bin/omarchy-capture-screenrecording" --prompt
[[ ! -f $PAUSED_FILE ]] || fail "resume choice clears the paused marker"
grep -qx -- '-SIGUSR2 -f ^gpu-screen-recorder' "$PKILL_LOG" || \
  fail "resume choice sends SIGUSR2" "$(cat "$PKILL_LOG")"
pass "resume choice resumes the capture"

# Stop choice -> SIGINT, never SIGUSR2.
echo active >"$PGREP_STATE"
rm -f "$PAUSED_FILE"
: >"$PKILL_LOG"
OMARCHY_TEST_SELECT_CHOICE="Stop recording" "$ROOT/bin/omarchy-capture-screenrecording" --prompt
grep -qx -- '-SIGINT -f ^gpu-screen-recorder' "$PKILL_LOG" || \
  fail "stop choice sends SIGINT" "$(cat "$PKILL_LOG")"
! grep -q -- '-SIGUSR2' "$PKILL_LOG" || fail "stop choice does not send SIGUSR2"
pass "stop choice stops the capture"

# The picker gets the right options per state: pause option when recording,
# resume option when paused.
echo active >"$PGREP_STATE"
rm -f "$PAUSED_FILE"
: >"$SELECT_LOG"
OMARCHY_TEST_SELECT_CHOICE="Pause recording" "$ROOT/bin/omarchy-capture-screenrecording" --prompt >/dev/null
grep -Fx -- 'Screen recording' "$SELECT_LOG" >/dev/null || fail "picker prompt is 'Screen recording'" "$(cat "$SELECT_LOG")"
grep -Fq -- $'\uf04c\tPause recording' "$SELECT_LOG" || fail "recording state offers Pause" "$(cat "$SELECT_LOG")"
grep -Fq -- $'\uf04d\tStop recording' "$SELECT_LOG" || fail "recording state offers Stop" "$(cat "$SELECT_LOG")"
! grep -Fq -- $'\uf04b\tResume recording' "$SELECT_LOG" || fail "recording state does not offer Resume" "$(cat "$SELECT_LOG")"

echo active >"$PGREP_STATE"
touch "$PAUSED_FILE"
: >"$SELECT_LOG"
OMARCHY_TEST_SELECT_CHOICE="Resume recording" "$ROOT/bin/omarchy-capture-screenrecording" --prompt >/dev/null
grep -Fq -- $'\uf04b\tResume recording' "$SELECT_LOG" || fail "paused state offers Resume" "$(cat "$SELECT_LOG")"
grep -Fq -- $'\uf04d\tStop recording' "$SELECT_LOG" || fail "paused state offers Stop" "$(cat "$SELECT_LOG")"
! grep -Fq -- $'\uf04c\tPause recording' "$SELECT_LOG" || fail "paused state does not offer Pause" "$(cat "$SELECT_LOG")"
pass "picker offers the two actions valid for the current state"

# Cancel -> nothing runs, exits nonzero, no signal.
echo active >"$PGREP_STATE"
: >"$PKILL_LOG"
if OMARCHY_TEST_SELECT_CANCEL=true "$ROOT/bin/omarchy-capture-screenrecording" --prompt; then
  fail "cancel exits nonzero"
fi
[[ ! -s $PKILL_LOG ]] || fail "cancel sends no signal" "$(cat "$PKILL_LOG")"
pass "cancel sends no signal and exits nonzero"

# No active recording -> --prompt opens the start menu, sends no signal.
echo inactive >"$PGREP_STATE"
: >"$MENU_LOG"
: >"$PKILL_LOG"
"$ROOT/bin/omarchy-capture-screenrecording" --prompt
grep -Fx -- 'toggle trigger.capture.screenrecord' "$MENU_LOG" >/dev/null || \
  fail "idle prompt opens the screenrecord menu" "$(cat "$MENU_LOG")"
[[ ! -s $PKILL_LOG ]] || fail "idle prompt sends no signal" "$(cat "$PKILL_LOG")"
pass "idle prompt opens the start menu instead of signaling"
