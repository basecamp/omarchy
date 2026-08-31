#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

SCRIPT="$ROOT/bin/omarchy-capture-screenrecording"
test_dir=$(mktemp -d)
tracked_pids=()
cleanup() {
  local pid
  for pid in "${tracked_pids[@]:-}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  rm -rf "$test_dir"
}
trap cleanup EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/gpu-screen-recorder" <<'PY'
#!/usr/bin/python3
import os
import signal
import sys
import time

args = sys.argv[1:]
output = args[args.index("-o") + 1]
with open(os.environ["RECORDER_PID_LOG"], "a", encoding="utf-8") as log:
    log.write(f"{os.getpid()}\n")

def finish(signum, _frame):
    with open(os.environ["RECORDER_SIGNAL_LOG"], "a", encoding="utf-8") as log:
        log.write(f"{os.getpid()}:{signum}\n")
    raise SystemExit(0)

signal.signal(signal.SIGINT, finish)
signal.signal(signal.SIGTERM, finish)
delay = float(os.environ.get("RECORDER_OUTPUT_DELAY", "0"))
deadline = time.monotonic() + delay
while time.monotonic() < deadline:
    time.sleep(0.02)
with open(output, "w", encoding="utf-8") as recording:
    recording.write("RECORDED\n")
while True:
    time.sleep(0.05)
PY

cat >"$stub_bin/mpv" <<'PY'
#!/usr/bin/python3
import os
import signal
import time

with open(os.environ["WEBCAM_PID_LOG"], "a", encoding="utf-8") as log:
    log.write(f"{os.getpid()}\n")
signal.signal(signal.SIGTERM, lambda _signum, _frame: exit(0))
while True:
    time.sleep(0.05)
PY

cat >"$stub_bin/ffprobe" <<'SH'
#!/bin/bash
printf 'ffprobe\t%s\n' "$*" >>"$MEDIA_LOG"
[[ $* == *packet=flags* && ${FFPROBE_DISCARDABLE:-false} == "true" ]] && printf 'D\n'
[[ $* == *stream=codec_type* && ${FFPROBE_AUDIO:-false} == "true" ]] && printf 'audio\n'
exit 0
SH

cat >"$stub_bin/ffmpeg" <<'SH'
#!/bin/bash
args=("$@")
output=${args[${#args[@]} - 3]}
printf 'ffmpeg\t%s\n' "$*" >>"$MEDIA_LOG"
if [[ $output == *preview.*.png ]]; then
  [[ ${FFMPEG_FAIL_PREVIEW:-false} != "true" ]] || exit 1
  printf 'PREVIEW\n' >"$output"
  [[ ${FFMPEG_UNSAFE_PREVIEW:-false} != "true" ]] || /usr/bin/chmod 0644 "$output"
else
  [[ ${FFMPEG_FAIL_PROCESS:-false} != "true" ]] || exit 1
  printf 'PROCESSED\n' >"$output"
  [[ ${FFMPEG_UNSAFE_PROCESS:-false} != "true" ]] || /usr/bin/chmod 0644 "$output"
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
echo DP-1
SH

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
case ${1:-} in
clients) printf '[{"title":"WebcamOverlay"}]\n' ;;
monitors) printf '[{"focused":true,"width":1920,"height":1080}]\n' ;;
esac
SH

cat >"$stub_bin/v4l2-ctl" <<'SH'
#!/bin/bash
printf '640x360\n'
SH

cat >"$stub_bin/omarchy-capture-webcam-resize" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf 'shell\t%s\n' "$*" >>"$UI_LOG"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify\t%s\n' "$*" >>"$UI_LOG"
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$PATH"
export RECORDER_PID_LOG="$test_dir/recorder.pids"
export RECORDER_SIGNAL_LOG="$test_dir/recorder.signals"
export WEBCAM_PID_LOG="$test_dir/webcam.pids"
export MEDIA_LOG="$test_dir/media.log"
export UI_LOG="$test_dir/ui.log"

wait_for_file() {
  local file="$1" index
  for ((index = 0; index < 200; index++)); do
    [[ -s $file ]] && return 0
    /usr/bin/sleep 0.01
  done
  return 1
}

wait_for_dead() {
  local pid="$1" index
  for ((index = 0; index < 200; index++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    /usr/bin/sleep 0.01
  done
  return 1
}

process_start() {
  local pid="$1" stat_line remainder
  local -a fields=()
  stat_line=$(</proc/$pid/stat)
  remainder=${stat_line##*) }
  read -r -a fields <<<"$remainder"
  printf '%s\n' "${fields[19]}"
}

new_case() {
  local name="$1"
  CASE_DIR="$test_dir/cases/$name"
  XDG_RUNTIME_DIR="$CASE_DIR/runtime"
  OMARCHY_SCREENRECORD_DIR="$CASE_DIR/Videos"
  STATE_DIR="$XDG_RUNTIME_DIR/omarchy-screenrecord"
  STATE_FILE="$STATE_DIR/recording.state"
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR" "$OMARCHY_SCREENRECORD_DIR"
  export XDG_RUNTIME_DIR OMARCHY_SCREENRECORD_DIR
  : >"$RECORDER_PID_LOG"
  : >"$RECORDER_SIGNAL_LOG"
  : >"$WEBCAM_PID_LOG"
  : >"$MEDIA_LOG"
  : >"$UI_LOG"
  unset RECORDER_OUTPUT_DELAY FFMPEG_FAIL_PROCESS FFMPEG_FAIL_PREVIEW
  unset FFMPEG_UNSAFE_PROCESS FFMPEG_UNSAFE_PREVIEW FFPROBE_DISCARDABLE FFPROBE_AUDIO
}

load_state_fields() {
  local line pattern tab=$'\t'
  line=$(<"$STATE_FILE")
  pattern="^version=1${tab}pid=([1-9][0-9]*)${tab}start=([1-9][0-9]*)${tab}webcam_pid=(0|[1-9][0-9]*)${tab}webcam_start=(0|[1-9][0-9]*)${tab}file=(/[^[:cntrl:]]+)$"
  [[ $line =~ $pattern ]] || fail "test fixture could not parse recording state" "$line"
  STATE_PID=${BASH_REMATCH[1]}
  STATE_START=${BASH_REMATCH[2]}
  STATE_WEBCAM_PID=${BASH_REMATCH[3]}
  STATE_WEBCAM_START=${BASH_REMATCH[4]}
  STATE_PATH=${BASH_REMATCH[5]}
}

initialize_empty_state_dir() {
  "$SCRIPT" --stop-recording >/dev/null 2>&1 || true
  [[ -d $STATE_DIR ]] || fail "screen recorder initializes its private state directory"
}

write_state() {
  local pid="$1" start="$2" path="$3" webcam_pid="${4:-0}" webcam_start="${5:-0}"
  printf 'version=1\tpid=%s\tstart=%s\twebcam_pid=%s\twebcam_start=%s\tfile=%s\n' \
    "$pid" "$start" "$webcam_pid" "$webcam_start" "$path" >"$STATE_FILE"
  chmod 0600 "$STATE_FILE"
}

new_case lifecycle
OMARCHY_SCREENRECORD_DEBUG=true "$SCRIPT" --fullscreen >"$CASE_DIR/start.output"
[[ $(stat -c '%a:%u' "$STATE_DIR") == "700:$(id -u)" ]] ||
  fail "recording runtime boundary is caller-owned mode 0700"
[[ $(stat -c '%a:%u:%h' "$STATE_FILE") == "600:$(id -u):1" ]] ||
  fail "recording state is a private single-link mode-0600 file"
[[ $(wc -l <"$STATE_FILE") == 1 ]] || fail "recording state is not exactly one line"
[[ $(stat -c '%a' "$STATE_DIR/screenrecording.log") == 600 ]] ||
  fail "debug log is not private"
load_state_fields
tracked_pids+=("$STATE_PID")
kill -0 "$STATE_PID" 2>/dev/null || fail "published recorder PID is not live"
[[ $(process_start "$STATE_PID") == "$STATE_START" ]] || fail "state does not bind the recorder start time"
stop_output=$("$SCRIPT" --stop-recording)
wait_for_dead "$STATE_PID" || fail "authenticated recorder survives a normal stop"
[[ $stop_output == "$STATE_PATH" ]] || fail "successful stop does not print the recorded path" "$stop_output"
[[ $(<"$STATE_PATH") == "PROCESSED" ]] || fail "successful recording is not finalized"
[[ ! -e $STATE_FILE && ! -L $STATE_FILE ]] || fail "successful stop leaves recording state"
pass "real stubbed start/stop lifecycle uses private PID-bound state and finalizes safely"

new_case codec-failure
"$SCRIPT" --fullscreen >/dev/null
load_state_fields
tracked_pids+=("$STATE_PID")
FFMPEG_FAIL_PROCESS=true "$SCRIPT" --stop-recording >/dev/null
wait_for_dead "$STATE_PID" || fail "recorder survives codec failure stop"
[[ $(<"$STATE_PATH") == "RECORDED" ]] || fail "codec failure damages the original recording"
! find "$OMARCHY_SCREENRECORD_DIR" -name '.omarchy-screenrecord-processed.*' -print -quit | grep -q . ||
  fail "codec failure leaks a processed temporary"
[[ ! -e $STATE_FILE ]] || fail "codec failure leaves recording state"
pass "codec failure preserves the original and cleans process/state temporaries"

new_case media-validation-failure
"$SCRIPT" --fullscreen >/dev/null
load_state_fields
tracked_pids+=("$STATE_PID")
if FFMPEG_UNSAFE_PROCESS=true "$SCRIPT" --stop-recording >/dev/null 2>&1; then
  fail "unsafe codec output validation reports success"
fi
wait_for_dead "$STATE_PID" || fail "recorder survives codec-output validation failure"
! find "$OMARCHY_SCREENRECORD_DIR" -name '.omarchy-screenrecord-processed.*' -print -quit | grep -q . ||
  fail "validation failure leaks a processed temporary"
[[ ! -e $STATE_FILE ]] || fail "validation failure leaves recording state"

new_case preview-validation-failure
"$SCRIPT" --fullscreen >/dev/null
load_state_fields
tracked_pids+=("$STATE_PID")
FFMPEG_UNSAFE_PREVIEW=true "$SCRIPT" --stop-recording >/dev/null
wait_for_dead "$STATE_PID" || fail "recorder survives preview validation failure"
! find "$STATE_DIR" -name 'preview.*.png' -print -quit | grep -q . ||
  fail "preview validation failure leaks a private temporary"
pass "media validation failures clean processed and preview temporaries"

new_case missing-output
"$SCRIPT" --fullscreen >/dev/null
load_state_fields
tracked_pids+=("$STATE_PID")
rm -- "$STATE_PATH"
: >"$MEDIA_LOG"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then
  fail "missing recorded output reports a successful stop"
fi
wait_for_dead "$STATE_PID" || fail "missing output leaves the authenticated recorder running"
[[ ! -s $MEDIA_LOG ]] || fail "missing output is passed to a media parser"
[[ ! -e $STATE_FILE ]] || fail "missing output leaves stale state"

new_case replaced-output
"$SCRIPT" --fullscreen >/dev/null
load_state_fields
tracked_pids+=("$STATE_PID")
replacement_target="$CASE_DIR/attacker-selected.mp4"
printf 'DO-NOT-CHANGE\n' >"$replacement_target"
rm -- "$STATE_PATH"
ln -s "$replacement_target" "$STATE_PATH"
: >"$MEDIA_LOG"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then
  fail "replaced recorded output reports a successful stop"
fi
wait_for_dead "$STATE_PID" || fail "replaced output leaves the authenticated recorder running"
[[ $(<"$replacement_target") == "DO-NOT-CHANGE" ]] || fail "replacement target is modified"
[[ ! -s $MEDIA_LOG ]] || fail "replaced output is passed to a media parser"
pass "missing or replaced output still stops only the bound recorder without media access"

new_case malformed-state
initialize_empty_state_dir
state_target="$CASE_DIR/state-target"
printf 'victim-state\n' >"$state_target"
ln -s "$state_target" "$STATE_FILE"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "symlinked recording state is accepted"; fi
[[ $(<"$state_target") == "victim-state" ]] || fail "symlinked state target is modified"
[[ -L $STATE_FILE ]] || fail "unsafe state symlink is silently replaced"
rm -- "$STATE_FILE"
printf 'not-state\n' >"$STATE_FILE"
chmod 0600 "$STATE_FILE"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "malformed recording state is accepted"; fi
[[ $(<"$STATE_FILE") == "not-state" ]] || fail "malformed state is rewritten"
rm -- "$STATE_FILE"
printf 'version=1\npid=1\n' >"$STATE_FILE"
chmod 0600 "$STATE_FILE"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "multiline recording state is accepted"; fi
[[ $(wc -l <"$STATE_FILE") == 2 ]] || fail "multiline state is rewritten"
rm -- "$STATE_FILE"
/usr/bin/sleep 30 &
wrong_mode_pid=$!
tracked_pids+=("$wrong_mode_pid")
wrong_mode_start=$(process_start "$wrong_mode_pid")
wrong_mode_path="$OMARCHY_SCREENRECORD_DIR/screenrecording-2026-08-31_12-00-00.mp4"
printf 'UNCHANGED\n' >"$wrong_mode_path"
write_state "$wrong_mode_pid" "$wrong_mode_start" "$wrong_mode_path"
chmod 0644 "$STATE_FILE"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "permissive recording state mode is accepted"; fi
kill -0 "$wrong_mode_pid" 2>/dev/null || fail "unsafe-mode state signals its selected PID"
[[ $(stat -c '%a' "$STATE_FILE") == 644 ]] || fail "unsafe-mode state is rewritten"
pass "symlinked, malformed, multiline, and permissive-mode state is rejected unchanged"

new_case pid-reuse
initialize_empty_state_dir
/usr/bin/sleep 30 &
reused_pid=$!
tracked_pids+=("$reused_pid")
reused_start=$(process_start "$reused_pid")
reused_path="$OMARCHY_SCREENRECORD_DIR/screenrecording-2026-08-31_12-00-00.mp4"
printf 'UNCHANGED\n' >"$reused_path"
write_state "$reused_pid" "$((reused_start + 1))" "$reused_path"
: >"$MEDIA_LOG"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "PID start-time mismatch is accepted"; fi
kill -0 "$reused_pid" 2>/dev/null || fail "PID-reuse defense signals the mismatched process"
[[ ! -s $MEDIA_LOG ]] || fail "stale PID state reaches media tools"
[[ ! -e $STATE_FILE ]] || fail "stale PID state is not cleaned"
pass "PID reuse/start-time mismatch is rejected without signaling the recycled process"

new_case prefix-collision
initialize_empty_state_dir
prefix_dir="$CASE_DIR/Videos-evil"
mkdir -m 0700 "$prefix_dir"
prefix_path="$prefix_dir/screenrecording-2026-08-31_12-00-00.mp4"
"$stub_bin/gpu-screen-recorder" -o "$prefix_path" &
prefix_pid=$!
tracked_pids+=("$prefix_pid")
wait_for_file "$prefix_path" || fail "prefix-collision recorder did not create output"
prefix_start=$(process_start "$prefix_pid")
write_state "$prefix_pid" "$prefix_start" "$prefix_path"
: >"$MEDIA_LOG"
if "$SCRIPT" --stop-recording >/dev/null 2>&1; then fail "output-directory prefix collision reports success"; fi
wait_for_dead "$prefix_pid" || fail "prefix collision leaves the bound recorder alive"
[[ $(<"$prefix_path") == "RECORDED" ]] || fail "prefix-collision path is modified"
[[ ! -s $MEDIA_LOG ]] || fail "prefix-collision path reaches media tools"
pass "output-directory escapes and prefix collisions never reach media processing"

new_case webcam-pre-recorder-failure
for offset in 0 1 2 3; do
  collision="$OMARCHY_SCREENRECORD_DIR/screenrecording-$(/usr/bin/date -d "+$offset seconds" +'%Y-%m-%d_%H-%M-%S').mp4"
  printf 'EXISTING\n' >"$collision"
done
if "$SCRIPT" --fullscreen --resolution=0x0 --with-webcam --webcam-device=/dev/video42 >/dev/null 2>&1; then
  fail "post-webcam filename collision reports success"
fi
wait_for_file "$WEBCAM_PID_LOG" || fail "webcam failure regression did not launch the overlay"
webcam_pid=$(tail -n 1 "$WEBCAM_PID_LOG")
tracked_pids+=("$webcam_pid")
wait_for_dead "$webcam_pid" || fail "post-webcam/pre-recorder failure leaks the camera process"
[[ ! -s $RECORDER_PID_LOG ]] || fail "filename collision launches the recorder"
[[ ! -e $STATE_FILE && ! -e $STATE_DIR/region ]] || fail "webcam launch failure leaves runtime state"
pass "post-webcam/pre-recorder failures clean the bound camera process and state"

new_case interrupted-start
export RECORDER_OUTPUT_DELAY=5
"$SCRIPT" --fullscreen >/dev/null 2>&1 &
runner_pid=$!
wait_for_file "$RECORDER_PID_LOG" || fail "interrupted start did not launch recorder"
interrupted_pid=$(tail -n 1 "$RECORDER_PID_LOG")
tracked_pids+=("$runner_pid" "$interrupted_pid")
kill -TERM "$runner_pid"
wait "$runner_pid" 2>/dev/null || true
wait_for_dead "$interrupted_pid" || fail "signal during start leaks the recorder process"
[[ ! -e $STATE_FILE ]] || fail "signal during start leaves published state"
unset RECORDER_OUTPUT_DELAY
pass "signals during startup clean the exact pending recorder"

new_case startup-timeout
timeout_script="$CASE_DIR/omarchy-capture-screenrecording"
sed 's/attempt < 75/attempt < 3/' "$SCRIPT" >"$timeout_script"
chmod 0755 "$timeout_script"
export RECORDER_OUTPUT_DELAY=5
if "$timeout_script" --fullscreen >"$CASE_DIR/timeout.output" 2>"$CASE_DIR/timeout.error"; then
  fail "a recorder that never publishes output reports successful startup"
fi
wait_for_file "$RECORDER_PID_LOG" || fail "startup-timeout regression did not launch the recorder"
timeout_recorder_pid=$(tail -n 1 "$RECORDER_PID_LOG")
tracked_pids+=("$timeout_recorder_pid")
wait_for_dead "$timeout_recorder_pid" || fail "startup timeout leaks the pending recorder"
[[ ! -e $STATE_FILE ]] || fail "startup timeout publishes stale recording state"
grep -qF 'did not create its output' "$CASE_DIR/timeout.error" ||
  fail "startup timeout lacks a useful error"
unset RECORDER_OUTPUT_DELAY
pass "recorder startup is bounded and cleans a process that never creates output"

new_case concurrent
"$SCRIPT" --fullscreen >/dev/null 2>&1 &
first_runner=$!
"$SCRIPT" --fullscreen >/dev/null 2>&1 &
second_runner=$!
first_status=0
second_status=0
wait "$first_runner" || first_status=$?
wait "$second_runner" || second_status=$?
((first_status == 0 && second_status == 0)) ||
  fail "serialized concurrent toggle invocations fail" "$first_status/$second_status"
[[ $(wc -l <"$RECORDER_PID_LOG") == 1 ]] || fail "concurrent invocations launch multiple recorders"
concurrent_pid=$(<"$RECORDER_PID_LOG")
tracked_pids+=("$concurrent_pid")
wait_for_dead "$concurrent_pid" || fail "concurrent toggle leaves recorder running"
[[ ! -e $STATE_FILE ]] || fail "concurrent toggle leaves recording state"
pass "concurrent invocations serialize and cannot cross recorder sessions"

(
  source "$SCRIPT"
  CURRENT_UID=$(id -u)
  unsafe_runtime="$test_dir/unsafe-runtime"
  mkdir -m 0777 "$unsafe_runtime"
  if runtime_dir_safe "$unsafe_runtime"; then
    exit 1
  fi
  safe_runtime="$test_dir/safe-runtime"
  mkdir -m 0700 "$safe_runtime"
  runtime_dir_safe "$safe_runtime"
  ln -s "$safe_runtime" "$test_dir/runtime-link"
  if runtime_dir_safe "$test_dir/runtime-link"; then
    exit 1
  fi
  if runtime_dir_safe "/run/user/$CURRENT_UID"; then
    XDG_RUNTIME_DIR=$unsafe_runtime
    resolve_runtime_base
    [[ $RUNTIME_BASE == "/run/user/$CURRENT_UID" ]]
  fi
) || fail "runtime validator accepts unsafe mode or symlink fallback"
pass "runtime selection rejects unsafe or symlinked fallback boundaries"

(
  source "$SCRIPT"
  CURRENT_UID=$(id -u)
  config_home="$test_dir/config-home"
  mkdir -m 0700 -p "$config_home/.config"
  chmod 0700 "$config_home/.config"
  printf 'XDG_VIDEOS_DIR="$HOME/Videos"\n' >"$config_home/.config/user-dirs.dirs"
  chmod 0600 "$config_home/.config/user-dirs.dirs"
  user_dirs_config_safe "$config_home/.config" "$config_home/.config/user-dirs.dirs"
  mv "$config_home/.config/user-dirs.dirs" "$config_home/real-user-dirs"
  ln -s "$config_home/real-user-dirs" "$config_home/.config/user-dirs.dirs"
  if user_dirs_config_safe "$config_home/.config" "$config_home/.config/user-dirs.dirs"; then
    exit 1
  fi
) || fail "user-dirs config validator accepts a symlinked source file"
pass "user-dirs shell config is sourced only from a private regular account-owned path"

(
  source "$SCRIPT"
  CURRENT_UID=$(id -u)
  STATE_DIR="$test_dir/chmod-runtime"
  OUTPUT_DIR="$test_dir/chmod-output"
  mkdir -m 0700 "$STATE_DIR" "$OUTPUT_DIR"
  recording="$OUTPUT_DIR/screenrecording-2026-08-31_12-00-00.mp4"
  printf 'ORIGINAL\n' >"$recording"
  chmod 0600 "$recording"
  set_private_mode() { return 1; }
  if finalize_recording "$recording"; then
    exit 1
  fi
  if create_preview "$recording" >/dev/null; then
    exit 1
  fi
  ! find "$OUTPUT_DIR" -name '.omarchy-screenrecord-processed.*' -print -quit | grep -q .
  ! find "$STATE_DIR" -name 'preview.*.png' -print -quit | grep -q .
) || fail "injected private-mode failure leaks media temporaries"
pass "injected chmod failures clean all newly allocated media temporaries"

! rg -n '\b(pgrep|pkill)\b|/tmp/omarchy-screenrecord' "$SCRIPT" >/dev/null ||
  fail "screen recorder retains system-wide process authorization or shared predictable state"
pass "screen recorder contains no system-wide process matching or shared predictable state"

cross_uid_probe="$test_dir/cross-uid-screenrecord-probe.sh"
cat >"$cross_uid_probe" <<'PROBE'
#!/bin/bash
set -euo pipefail

mount --bind "$PROBE_ROOT" /mnt
mount -t tmpfs -o mode=1777 tmpfs /tmp
mkdir -m 0755 /tmp/stubs
cat >/tmp/stubs/omarchy-notification-send <<'SH'
#!/bin/bash
exit 0
SH
chmod 0755 /tmp/stubs/omarchy-notification-send

mkdir -m 0700 /tmp/runtime-victim /tmp/Videos
chown 1000:1000 /tmp/runtime-victim /tmp/Videos
target=/tmp/Videos/attacker-selected.mp4
printf 'VICTIM-ORIGINAL\n' >"$target"
chown 1000:1000 "$target"
chmod 0600 "$target"

setpriv --reuid=1001 --regid=1001 --clear-groups bash -c 'printf "%s\n" "$1" > /tmp/omarchy-screenrecord-filename' _ "$target"
[[ $(stat -c '%u' /tmp/omarchy-screenrecord-filename) == 1001 ]]

if setpriv --reuid=1000 --regid=1000 --clear-groups env PATH=/tmp/stubs:/usr/bin XDG_RUNTIME_DIR=/tmp/runtime-victim OMARCHY_SCREENRECORD_DIR=/tmp/Videos /mnt/bin/omarchy-capture-screenrecording --stop-recording 2>/dev/null; then
  exit 2
fi

[[ $(<"$target") == "VICTIM-ORIGINAL" ]]
[[ $(stat -c '%u' /tmp/omarchy-screenrecord-filename) == 1001 ]]
[[ $(< /tmp/omarchy-screenrecord-filename) == "$target" ]]
[[ $(stat -c '%u:%a' /tmp/runtime-victim/omarchy-screenrecord) == "1000:700" ]]

foreign_state=/tmp/runtime-victim/omarchy-screenrecord/recording.state
printf 'version=1\tpid=1\tstart=1\twebcam_pid=0\twebcam_start=0\tfile=%s\n' "$target" >"$foreign_state"
chown 1001:1001 "$foreign_state"
chmod 0600 "$foreign_state"
if setpriv --reuid=1000 --regid=1000 --clear-groups env PATH=/tmp/stubs:/usr/bin XDG_RUNTIME_DIR=/tmp/runtime-victim OMARCHY_SCREENRECORD_DIR=/tmp/Videos /mnt/bin/omarchy-capture-screenrecording --stop-recording 2>/dev/null; then
  exit 3
fi
[[ $(stat -c '%u' "$foreign_state") == 1001 ]]
[[ $(<"$target") == "VICTIM-ORIGINAL" ]]
rm -- "$foreign_state"
if setpriv --reuid=1001 --regid=1001 --clear-groups touch /tmp/runtime-victim/omarchy-screenrecord/recording.state 2>/dev/null; then
  exit 4
fi
PROBE
chmod +x "$cross_uid_probe"

if unshare --user --map-auto --map-root-user true 2>/dev/null; then
  if PROBE_ROOT="$ROOT" unshare --user --map-auto --map-root-user --mount "$cross_uid_probe"; then
    pass "a second UID cannot steer stop/finalization through pre-created shared state"
  else
    fail "second-UID shared-state probe fails under available user/mount namespaces"
  fi
else
  pass "user/mount namespaces unavailable; skipping second-UID shared-state probe"
fi
