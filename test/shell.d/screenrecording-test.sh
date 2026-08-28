#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/v4l2-ctl" <<'SH'
#!/bin/bash

[[ ${OMARCHY_TEST_NO_WEBCAM:-false} == "true" ]] && exit 0

case "$1" in
--list-devices)
  printf '%s\n' "ipu6 (PCI:0000:00:05.0):"
  printf '\t%s\n' "/dev/video0"
  printf '\t%s\n' "/dev/video1"

  if [[ ${OMARCHY_TEST_RAW_WEBCAM:-false} != "true" ]]; then
    printf '\n%s\n' "Built-in Webcam: Integrated Camera"
    printf '\t%s\n' "/dev/video42"
    printf '\t%s\n' "/dev/video43"
    printf '\n%s\n' "USB Capture Card: External Camera"
    printf '\t%s\n' "/dev/video2"
  fi

  if [[ ${OMARCHY_TEST_DUAL_NODE_WEBCAM:-false} == "true" ]]; then
    printf '\n%s\n' "Dual Node Camera: ISP Wrapper"
    printf '\t%s\n' "/dev/video7"
    printf '\t%s\n' "/dev/video8"
    printf '\n%s\n' "Metadata Only: Sensor"
    printf '\t%s\n' "/dev/video9"
  fi
  ;;
--device)
  case "$2" in
  /dev/video0) device_capability="Video Output" ;;
  /dev/video1) device_capability="Metadata Capture" ;;
  /dev/video7 | /dev/video9) device_capability="Video Output" ;;
  *) device_capability="Video Capture" ;;
  esac

  printf '%s\n' \
    "Driver Info:" \
    $'\tCapabilities     : 0x84a00001' \
    $'\t\tVideo Capture' \
    $'\tDevice Caps      : 0x04200001' \
    $'\t\t'"$device_capability"
  ;;
esac
SH

cat >"$stub_bin/omarchy-menu-select" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_MENU_ARGS"
printf '%s\n' "$3"
SH

cat >"$stub_bin/omarchy-capture-screenrecording" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_RECORDER_ARGS"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFICATION_ARGS"
SH

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$ROOT/bin:$PATH"
# The resize helper anchors to a region file here, so keep it out of the real one
export XDG_RUNTIME_DIR="$tmp_dir"
export OMARCHY_TEST_MENU_ARGS="$tmp_dir/menu-args"
export OMARCHY_TEST_RECORDER_ARGS="$tmp_dir/recorder-args"
export OMARCHY_TEST_NOTIFICATION_ARGS="$tmp_dir/notification-args"

mapfile -t capture_devices < <(omarchy-capture-webcam-list)
expected_capture_devices=(
  "/dev/video42  Built-in Webcam: Integrated Camera"
  "/dev/video2  USB Capture Card: External Camera"
)

if [[ ${capture_devices[*]} != "${expected_capture_devices[*]}" ]]; then
  fail "webcam detection filters output-only devices and collapses each capture group" \
    "expected: ${expected_capture_devices[*]}\nactual:   ${capture_devices[*]}"
fi
pass "webcam detection filters output-only devices and collapses each capture group"

dual_node=$(OMARCHY_TEST_DUAL_NODE_WEBCAM=true omarchy-capture-webcam-list) ||
  fail "webcam listing exits zero when the trailing device is filtered"
pass "webcam listing exits zero when the trailing device is filtered"

expected_dual_node="/dev/video42  Built-in Webcam: Integrated Camera
/dev/video2  USB Capture Card: External Camera
/dev/video8  Dual Node Camera: ISP Wrapper"
[[ $dual_node == "$expected_dual_node" ]] ||
  fail "webcam detection falls through to a later capture-capable node in a group" "$dual_node"
pass "webcam detection falls through to a later capture-capable node in a group"

if "$ROOT/bin/omarchy-hw-webcam"; then
  pass "webcam hardware detection succeeds when a capture device is available"
else
  fail "webcam hardware detection succeeds when a capture device is available"
fi

if OMARCHY_TEST_RAW_WEBCAM=true "$ROOT/bin/omarchy-hw-webcam"; then
  fail "webcam hardware detection rejects output-only video devices"
else
  pass "webcam hardware detection rejects output-only video devices"
fi

if OMARCHY_TEST_NO_WEBCAM=true "$ROOT/bin/omarchy-hw-webcam"; then
  fail "webcam hardware detection fails when no video device is available"
else
  pass "webcam hardware detection fails when no video device is available"
fi

if OMARCHY_TEST_RAW_WEBCAM=true "$ROOT/bin/omarchy-capture-screenrecording-with-webcam"; then
  fail "screenrecording webcam picker rejects output-only video devices"
fi
grep -Fx 'No webcam devices found' "$OMARCHY_TEST_NOTIFICATION_ARGS" >/dev/null || \
  fail "screenrecording webcam picker reports no capture-capable device"
pass "screenrecording webcam picker rejects output-only video devices"

"$ROOT/bin/omarchy-capture-screenrecording-with-webcam"

expected_menu_args="$tmp_dir/expected-menu-args"
printf '%s\n' \
  "Select Webcam" \
  "/dev/video42  Built-in Webcam: Integrated Camera" \
  "/dev/video2  USB Capture Card: External Camera" \
  "--" \
  "--width" \
  "520" \
  "--maxheight" \
  "520" >"$expected_menu_args"

if ! cmp -s "$OMARCHY_TEST_MENU_ARGS" "$expected_menu_args"; then
  fail "screenrecording webcam picker passes each webcam as a menu option" "$(diff -u "$expected_menu_args" "$OMARCHY_TEST_MENU_ARGS")"
fi
pass "screenrecording webcam picker passes each webcam as a menu option"

expected_recorder_args="$tmp_dir/expected-recorder-args"
printf '%s\n' \
  "--with-desktop-audio" \
  "--with-microphone-audio" \
  "--with-webcam" \
  "--webcam-device=/dev/video2" >"$expected_recorder_args"

if ! cmp -s "$OMARCHY_TEST_RECORDER_ARGS" "$expected_recorder_args"; then
  fail "screenrecording webcam picker starts recording with selected device" "$(diff -u "$expected_recorder_args" "$OMARCHY_TEST_RECORDER_ARGS")"
fi
pass "screenrecording webcam picker starts recording with selected device"

first_webcam=$(omarchy-capture-webcam-list | sed -n '1s/[[:space:]].*//p')
[[ $first_webcam == "/dev/video42" ]] || fail "screenrecording auto-detection selects the first capture device"
grep -F 'WEBCAM_DEVICE=$(omarchy-capture-webcam-list' "$ROOT/bin/omarchy-capture-screenrecording" >/dev/null || \
  fail "screenrecording auto-detection uses capture-capable webcams"
pass "screenrecording auto-detection uses the first capture-capable webcam"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

case $1 in
clients)
  printf '[{"address":"0xabc","title":"%s","size":[%s,%s],"monitor":2}]\n' \
    "${OMARCHY_TEST_CLIENT_TITLE:-WebcamOverlay}" \
    "${OMARCHY_TEST_CLIENT_WIDTH:-178}" \
    "${OMARCHY_TEST_CLIENT_HEIGHT:-200}"
  ;;
monitors)
  printf '[{"id":2,"x":1280,"y":-100,"width":%s,"height":%s,"scale":%s}]\n' \
    "${OMARCHY_TEST_MONITOR_WIDTH:-2560}" \
    "${OMARCHY_TEST_MONITOR_HEIGHT:-1600}" \
    "${OMARCHY_TEST_MONITOR_SCALE:-2}"
  ;;
dispatch)
  printf '%s\n' "$*" >>"$OMARCHY_TEST_HYPRCTL_ARGS"
  ;;
esac
SH
chmod +x "$stub_bin/hyprctl"

export OMARCHY_TEST_HYPRCTL_ARGS="$tmp_dir/hyprctl-args"

"$ROOT/bin/omarchy-capture-webcam-resize" smaller

expected_hyprctl_args="$tmp_dir/expected-hyprctl-args"
printf '%s\n' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 128, y = 144 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 2392, y = 516 })' >"$expected_hyprctl_args"

if ! cmp -s "$OMARCHY_TEST_HYPRCTL_ARGS" "$expected_hyprctl_args"; then
  fail "webcam resize preserves its aspect ratio and corner anchor" "$(diff -u "$expected_hyprctl_args" "$OMARCHY_TEST_HYPRCTL_ARGS")"
fi
pass "webcam resize preserves its aspect ratio and corner anchor"

: >"$OMARCHY_TEST_HYPRCTL_ARGS"
OMARCHY_TEST_MONITOR_WIDTH=1920 \
  OMARCHY_TEST_MONITOR_HEIGHT=1080 \
  OMARCHY_TEST_MONITOR_SCALE=1 \
  OMARCHY_TEST_CLIENT_WIDTH=128 \
  OMARCHY_TEST_CLIENT_HEIGHT=144 \
  "$ROOT/bin/omarchy-capture-webcam-resize" reset

printf '%s\n' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 240, y = 270 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 2920, y = 670 })' >"$expected_hyprctl_args"

if ! cmp -s "$OMARCHY_TEST_HYPRCTL_ARGS" "$expected_hyprctl_args"; then
  fail "webcam default size adapts to monitor resolution" "$(diff -u "$expected_hyprctl_args" "$OMARCHY_TEST_HYPRCTL_ARGS")"
fi
pass "webcam default size adapts to monitor resolution"

: >"$OMARCHY_TEST_HYPRCTL_ARGS"
OMARCHY_TEST_CLIENT_TITLE="Other Window" "$ROOT/bin/omarchy-capture-webcam-resize" larger

if [[ -s $OMARCHY_TEST_HYPRCTL_ARGS ]]; then
  fail "webcam resize ignores other windows" "$(cat "$OMARCHY_TEST_HYPRCTL_ARGS")"
fi
pass "webcam resize ignores other windows"

region_file="$XDG_RUNTIME_DIR/omarchy-screenrecord-region"

: >"$OMARCHY_TEST_HYPRCTL_ARGS"
echo "800x600+100+100" >"$region_file"
"$ROOT/bin/omarchy-capture-webcam-resize" reset

printf '%s\n' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 133, y = 150 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 727, y = 510 })' >"$expected_hyprctl_args"

if ! cmp -s "$OMARCHY_TEST_HYPRCTL_ARGS" "$expected_hyprctl_args"; then
  fail "webcam anchors to the recorded region" "$(diff -u "$expected_hyprctl_args" "$OMARCHY_TEST_HYPRCTL_ARGS")"
fi
pass "webcam anchors to the recorded region"

printf '%s\n' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 178, y = 200 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 2342, y = 460 })' >"$expected_hyprctl_args"

for region in "not-a-region" ""; do
  : >"$OMARCHY_TEST_HYPRCTL_ARGS"
  printf '%s' "$region" >"$region_file"
  "$ROOT/bin/omarchy-capture-webcam-resize" reset

  if ! cmp -s "$OMARCHY_TEST_HYPRCTL_ARGS" "$expected_hyprctl_args"; then
    fail "webcam falls back to the monitor for an unusable region" "$(diff -u "$expected_hyprctl_args" "$OMARCHY_TEST_HYPRCTL_ARGS")"
  fi
done
pass "webcam falls back to the monitor for an unusable region"

# A region too narrow for presets scaled from its height shrinks the whole
# ladder, so the three sizes stay distinct and each one fits inside the margins
: >"$OMARCHY_TEST_HYPRCTL_ARGS"
echo "200x1200+0+0" >"$region_file"
for size in small medium large; do
  "$ROOT/bin/omarchy-capture-webcam-resize" "$size"
done

printf '%s\n' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 64, y = 72 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 96, y = 1088 })' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 89, y = 100 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 71, y = 1060 })' \
  'dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 120, y = 135 })' \
  'dispatch hl.dsp.window.move({ window = "address:0xabc", x = 40, y = 1025 })' >"$expected_hyprctl_args"

if ! cmp -s "$OMARCHY_TEST_HYPRCTL_ARGS" "$expected_hyprctl_args"; then
  fail "webcam sizes stay distinct and inside a narrow region" "$(diff -u "$expected_hyprctl_args" "$OMARCHY_TEST_HYPRCTL_ARGS")"
fi
pass "webcam sizes stay distinct and inside a narrow region"

rm -f "$region_file"

grep -F 'o.bind("SUPER + ALT + code:34", "Make webcam overlay smaller", "omarchy-capture-webcam-resize smaller")' \
  "$ROOT/default/hypr/bindings/utilities.lua" >/dev/null || fail "webcam smaller hotkey is configured"
grep -F 'o.bind("SUPER + ALT + code:35", "Make webcam overlay larger", "omarchy-capture-webcam-resize larger")' \
  "$ROOT/default/hypr/bindings/utilities.lua" >/dev/null || fail "webcam larger hotkey is configured"
pass "webcam resize hotkeys are configured"

grep -F -- '--wayland-app-id="WebcamOverlay-$WEBCAM_SIZE"' \
  "$ROOT/bin/omarchy-capture-screenrecording" >/dev/null || fail "webcam uses a dedicated size-specific app id"

webcam_rules="$ROOT/default/hypr/apps/webcam-overlay.lua"
grep -F 'move = { "(monitor_w-monitor_h*4/25-40)", "(monitor_h-monitor_h*9/50-40)" }' "$webcam_rules" >/dev/null || \
  fail "small webcam starts at its final corner position"
grep -F 'move = { "(monitor_w-monitor_h*2/9-40)", "(monitor_h-monitor_h/4-40)" }' "$webcam_rules" >/dev/null || \
  fail "medium webcam starts at its final corner position"
grep -F 'move = { "(monitor_w-monitor_h*3/10-40)", "(monitor_h-monitor_h*27/80-40)" }' "$webcam_rules" >/dev/null || \
  fail "large webcam starts at its final corner position"
pass "webcam size rules place the initial window in its final corner"

# --- loudnorm helpers (source the recorder without starting a capture) ---

source "$ROOT/bin/omarchy-capture-screenrecording"

quiet_loudnorm_json='{
	"input_i" : "-28.00",
	"input_tp" : "-8.00",
	"input_lra" : "8.00",
	"input_thresh" : "-38.00",
	"output_i" : "-14.00",
	"output_tp" : "-1.50",
	"output_lra" : "8.00",
	"output_thresh" : "-24.00",
	"normalization_type" : "dynamic",
	"target_offset" : "0.00"
}'
near_target_loudnorm_json='{
	"input_i" : "-14.20",
	"input_tp" : "-2.00",
	"input_lra" : "8.00",
	"input_thresh" : "-24.00",
	"output_i" : "-14.00",
	"output_tp" : "-1.50",
	"output_lra" : "8.00",
	"output_thresh" : "-24.00",
	"normalization_type" : "dynamic",
	"target_offset" : "0.20"
}'
wide_lra_loudnorm_json='{
	"input_i" : "-14.00",
	"input_tp" : "-1.80",
	"input_lra" : "18.00",
	"input_thresh" : "-32.00",
	"output_i" : "-14.00",
	"output_tp" : "-1.50",
	"output_lra" : "11.00",
	"output_thresh" : "-24.00",
	"normalization_type" : "dynamic",
	"target_offset" : "0.00"
}'
hot_loudnorm_json='{
	"input_i" : "-8.00",
	"input_tp" : "-1.20",
	"input_lra" : "8.00",
	"input_thresh" : "-18.00",
	"output_i" : "-14.00",
	"output_tp" : "-1.50",
	"output_lra" : "8.00",
	"output_thresh" : "-24.00",
	"normalization_type" : "dynamic",
	"target_offset" : "6.00"
}'
inf_loudnorm_json='{
	"input_i" : "-inf",
	"input_tp" : "-inf",
	"input_lra" : "0.00",
	"input_thresh" : "-70.00",
	"output_i" : "-14.00",
	"output_tp" : "-1.50",
	"output_lra" : "0.00",
	"output_thresh" : "-24.00",
	"normalization_type" : "dynamic",
	"target_offset" : "0.00"
}'

loudness_might_need_normalization -14.0 8.0 && fail "loudness already at -14 LUFS does not need normalization"
loudness_might_need_normalization -18.0 8.0 && fail "loudness at the -18 LUFS quiet threshold does not need normalization"
loudness_might_need_normalization -18.1 8.0 || fail "loudness quieter than -18 LUFS needs normalization"
loudness_might_need_normalization -11.0 8.0 && fail "loudness at the -11 LUFS loud threshold does not need normalization"
loudness_might_need_normalization -10.9 8.0 || fail "loudness louder than -11 LUFS needs normalization"
loudness_might_need_normalization -8.0 8.0 || fail "loudness at -8 LUFS needs normalization"
loudness_might_need_normalization -14.0 18.0 && fail "wide LRA inside the LUFS window does not need normalization"
loudness_might_need_normalization -inf 8.0 && fail "non-numeric loudness does not need normalization"
loudness_might_need_normalization "" 8.0 && fail "empty loudness does not need normalization"
pass "loudness_might_need_normalization asks outside -18 to -11 LUFS"

pop_only=$(screenrecord_audio_filter no)
[[ $pop_only == *loudnorm* ]] && fail "skipping loudnorm still mutes the PipeWire pop" "$pop_only"
[[ $pop_only == "volume=enable='lt(t,0.4)':volume=0,afade=t=in:st=0.4:d=0.05" ]] || \
  fail "skipping loudnorm still mutes the PipeWire pop" "$pop_only"
with_loudnorm=$(screenrecord_audio_filter yes)
[[ $with_loudnorm == *loudnorm=I=-14:TP=-1.5:LRA=11 ]] || fail "yes applies single-pass loudnorm" "$with_loudnorm"
[[ $with_loudnorm == volume=enable* ]] || fail "yes still mutes the PipeWire pop" "$with_loudnorm"
two_pass=$(screenrecord_audio_filter yes "$quiet_loudnorm_json")
[[ $two_pass == *measured_I=-28.00* ]] || fail "measured stats feed two-pass loudnorm" "$two_pass"
[[ $two_pass == *measured_LRA=8.00* ]] || fail "measured LRA feeds two-pass loudnorm" "$two_pass"
pass "screenrecord_audio_filter always mutes the pop and only adds loudnorm when asked"

NORMALIZE_AUDIO=true
[[ $(normalize_preference) == yes ]] || fail "invocation --normalize-audio prefers yes"
NORMALIZE_AUDIO=false
[[ $(normalize_preference) == no ]] || fail "invocation --no-normalize-audio prefers no"
NORMALIZE_AUDIO=""
OMARCHY_SCREENRECORD_NORMALIZE=true
[[ $(normalize_preference) == yes ]] || fail "OMARCHY_SCREENRECORD_NORMALIZE=true prefers yes"
OMARCHY_SCREENRECORD_NORMALIZE=false
[[ $(normalize_preference) == no ]] || fail "OMARCHY_SCREENRECORD_NORMALIZE=false prefers no"
NORMALIZE_AUDIO=true
OMARCHY_SCREENRECORD_NORMALIZE=false
[[ $(normalize_preference) == yes ]] || fail "invocation flags beat the env var"
NORMALIZE_AUDIO=""
unset OMARCHY_SCREENRECORD_NORMALIZE
echo yes >"$NORMALIZE_FILE"
[[ $(normalize_preference) == yes ]] || fail "start-time sidecar yes is honored at stop"
echo no >"$NORMALIZE_FILE"
[[ $(normalize_preference) == no ]] || fail "start-time sidecar no is honored at stop"
OMARCHY_SCREENRECORD_NORMALIZE=false
echo yes >"$NORMALIZE_FILE"
[[ $(normalize_preference) == no ]] || fail "env var beats the start-time sidecar"
unset OMARCHY_SCREENRECORD_NORMALIZE
rm -f "$NORMALIZE_FILE"
[[ $(normalize_preference) == ask ]] || fail "missing sidecar asks"
NORMALIZE_AUDIO=""
persist_normalize_preference
[[ $(cat "$NORMALIZE_FILE") == ask ]] || fail "start without flags persists ask"
NORMALIZE_AUDIO=true
persist_normalize_preference
[[ $(cat "$NORMALIZE_FILE") == yes ]] || fail "start --normalize-audio persists yes"
NORMALIZE_AUDIO=false
persist_normalize_preference
[[ $(cat "$NORMALIZE_FILE") == no ]] || fail "start --no-normalize-audio persists no"
NORMALIZE_AUDIO=""
rm -f "$NORMALIZE_FILE"
pass "normalize_preference prefers flags, then env, then the start sidecar"

cat >"$stub_bin/ffmpeg" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >>"$OMARCHY_TEST_FFMPEG_ARGS"
if printf '%s\n' "$@" | grep -q 'print_format=json'; then
  printf '%s\n' "${OMARCHY_TEST_LOUDNORM_JSON-}" >&2
  exit 0
fi
exit 0
SH
chmod +x "$stub_bin/ffmpeg"

cat >"$stub_bin/omarchy-menu-select" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_MENU_ARGS"
if [[ ${OMARCHY_TEST_MENU_EXIT:-0} != 0 ]]; then
  exit "$OMARCHY_TEST_MENU_EXIT"
fi
printf '%s\n' "${OMARCHY_TEST_MENU_REPLY-}"
SH
chmod +x "$stub_bin/omarchy-menu-select"

export OMARCHY_TEST_FFMPEG_ARGS="$tmp_dir/ffmpeg-args"
dummy_recording="$tmp_dir/dummy.mp4"
touch "$dummy_recording"

extracted=$(extract_loudnorm_json <<<"noise"$'\n'"$quiet_loudnorm_json"$'\n'"more")
[[ $extracted == "$quiet_loudnorm_json" ]] || fail "extract_loudnorm_json keeps the loudnorm object" "$extracted"
pass "extract_loudnorm_json keeps the loudnorm JSON object"

export OMARCHY_TEST_LOUDNORM_JSON="$quiet_loudnorm_json"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
measured=$(measure_loudness "$dummy_recording")
[[ $measured == *'"input_i" : "-28.00"'* ]] || fail "measure_loudness reads first-pass JSON" "$measured"
grep -q "print_format=json" "$OMARCHY_TEST_FFMPEG_ARGS" || fail "measure_loudness requests print_format=json"
grep -q "volume=enable='lt(t,0.4)':volume=0" "$OMARCHY_TEST_FFMPEG_ARGS" || \
  fail "measure_loudness applies the pop mute so the transient does not skew LUFS"
pass "measure_loudness runs an audio-only first pass with the pop mute"

unset OMARCHY_SCREENRECORD_NORMALIZE
NORMALIZE_AUDIO=""
rm -f "$NORMALIZE_FILE"
: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$near_target_loudnorm_json"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "near-target audio skips loudnorm"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "near-target audio does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize skips the prompt when I and LRA already match"

: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$quiet_loudnorm_json"
export OMARCHY_TEST_MENU_REPLY=$'Normalize\traise to typical YouTube and Spotify volume'
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == yes ]] || fail "quiet audio normalizes when the user accepts"
[[ $SCREENRECORD_LOUDNESS_STATS == *'"input_i" : "-28.00"'* ]] || \
  fail "accepting the prompt keeps first-pass stats for two-pass loudnorm" "$SCREENRECORD_LOUDNESS_STATS"
wired=$(screenrecord_audio_filter "$SCREENRECORD_NORMALIZE" "$SCREENRECORD_LOUDNESS_STATS")
[[ $wired == *measured_I=-28.00* ]] || fail "finalize wiring applies two-pass loudnorm" "$wired"
grep -q "Audio may be unintentionally quiet" "$OMARCHY_TEST_MENU_ARGS" || fail "quiet audio prompt explains the recording is quiet"
grep -q $'\tKeep original levels\tas recorded' "$OMARCHY_TEST_MENU_ARGS" || \
  fail "keep option uses empty glyph so the label is not drawn as an icon" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
grep -q $'\tNormalize\traise to typical YouTube and Spotify volume' "$OMARCHY_TEST_MENU_ARGS" || \
  fail "quiet normalize option says it will raise to typical streaming volume" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize prompts when audio is quiet"

: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$hot_loudnorm_json"
export OMARCHY_TEST_MENU_REPLY=$'Keep original levels\tas recorded'
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "hot -8 LUFS keeps original levels when the user declines"
grep -q "Audio may be unintentionally loud" "$OMARCHY_TEST_MENU_ARGS" || fail "hot audio prompt explains the recording is loud"
grep -q $'\tNormalize\tlower to typical YouTube and Spotify volume' "$OMARCHY_TEST_MENU_ARGS" || \
  fail "loud normalize option says it will lower to typical streaming volume" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize prompts when audio is louder than -11 LUFS"

: >"$OMARCHY_TEST_MENU_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$wide_lra_loudnorm_json"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "wide LRA on already-loud audio skips loudnorm"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "wide LRA on already-loud audio does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize skips the prompt when LRA is wide but loudness is inside the window"

: >"$OMARCHY_TEST_MENU_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$quiet_loudnorm_json"
export OMARCHY_TEST_MENU_EXIT=1
unset OMARCHY_TEST_MENU_REPLY
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "Esc keeps original levels"
pass "decide_normalize treats a cancelled prompt as keep original"

unset OMARCHY_TEST_MENU_EXIT
: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="$inf_loudnorm_json"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "silent/-inf audio skips loudnorm"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "-inf audio does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize skips the prompt for unusable loudness"

: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
export OMARCHY_TEST_LOUDNORM_JSON="not json"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "unreadable loudnorm JSON skips loudnorm"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "unreadable JSON does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
pass "decide_normalize skips the prompt when measurement fails"

: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
OMARCHY_SCREENRECORD_NORMALIZE=false
export OMARCHY_TEST_LOUDNORM_JSON="$quiet_loudnorm_json"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == no ]] || fail "env false skips loudnorm"
[[ -s $OMARCHY_TEST_FFMPEG_ARGS ]] && fail "env false does not measure" "$(cat "$OMARCHY_TEST_FFMPEG_ARGS")"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "env false does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
unset OMARCHY_SCREENRECORD_NORMALIZE
pass "env false overrides the prompt"

: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
NORMALIZE_AUDIO=true
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == yes ]] || fail "flag true applies loudnorm"
[[ -s $OMARCHY_TEST_FFMPEG_ARGS ]] && fail "flag true does not need a first pass" "$(cat "$OMARCHY_TEST_FFMPEG_ARGS")"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "flag true does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
NORMALIZE_AUDIO=""
pass "invocation flags override the prompt"

echo yes >"$NORMALIZE_FILE"
: >"$OMARCHY_TEST_MENU_ARGS"
: >"$OMARCHY_TEST_FFMPEG_ARGS"
decide_normalize "$dummy_recording"
[[ $SCREENRECORD_NORMALIZE == yes ]] || fail "sidecar yes applies loudnorm without prompting"
[[ -s $OMARCHY_TEST_MENU_ARGS ]] && fail "sidecar yes does not prompt" "$(cat "$OMARCHY_TEST_MENU_ARGS")"
rm -f "$NORMALIZE_FILE"
pass "start-time sidecar overrides the prompt"
