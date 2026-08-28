#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
call_log="$test_dir/calls"
sink_json="$test_dir/sinks.json"
mkdir -p "$stub_bin"
touch "$call_log"

cat >"$stub_bin/omarchy-audio-tuning" <<'STUB'
#!/bin/bash
[[ $1 == "fronted-sink" ]] && printf '%s\n' "${FRONTED_SINK:-}"
STUB

cat >"$stub_bin/wpctl" <<'STUB'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$CALL_LOG"
STUB

cat >"$stub_bin/pactl" <<'STUB'
#!/bin/bash
case "$*" in
  "get-default-sink")
    printf '%s\n' "${DEFAULT_SINK:-}"
    ;;
  "--format=json list sinks")
    cat "$SINK_JSON"
    ;;
  "list sink-inputs")
    cat <<'INPUTS'
Sink Input #10
    application.name = "Brave"
Sink Input #11
    application.name = "EasyEffects"
Sink Input #12
    media.name = "DSP output"
INPUTS
    ;;
  *)
    printf 'pactl %s\n' "$*" >>"$CALL_LOG"
    ;;
esac
STUB

chmod +x "$stub_bin/omarchy-audio-tuning" "$stub_bin/wpctl" "$stub_bin/pactl"

cat >"$sink_json" <<'JSON'
[
  {
    "name": "analog",
    "description": "Built-in Audio Analog Stereo",
    "active_port": "lineout",
    "ports": [
      {"name": "lineout", "description": "Line Out", "type": "Line", "availability": "available"},
      {"name": "headphones", "description": "Headphones", "type": "Headphones", "availability": "unknown"}
    ],
    "properties": {}
  },
  {
    "name": "usb",
    "description": "USB Headset",
    "ports": [],
    "properties": {"device.product.name": "USB Headset"}
  },
  {
    "name": "hdmi",
    "description": "Disconnected Display",
    "active_port": "hdmi-output-0",
    "ports": [
      {"name": "hdmi-output-0", "description": "HDMI", "availability": "not available"}
    ],
    "properties": {}
  },
  {
    "name": "fronted-physical",
    "description": "Physical Speakers",
    "ports": [],
    "properties": {}
  },
  {
    "name": "tuned-output",
    "description": "Speaker Tuning",
    "ports": [],
    "properties": {}
  }
]
JSON

export CALL_LOG="$call_log"
export SINK_JSON="$sink_json"
export DEFAULT_SINK=analog
export FRONTED_SINK=fronted-physical

targets=$(PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-audio-output-targets")
jq -e '
  length == 4
  and any(.[]; .sinkName == "analog" and .portName == "lineout" and .active == true)
  and any(.[]; .sinkName == "analog" and .portName == "headphones" and .active == false)
  and any(.[]; .sinkName == "usb" and .portName == "")
  and any(.[]; .sinkName == "tuned-output")
  and all(.[]; .sinkName != "hdmi" and .sinkName != "fronted-physical")
' <<<"$targets" >/dev/null || fail "audio output targets include usable ports and preserve tuning"
pass "audio output targets include usable ports and preserve tuning"

: >"$call_log"
PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-audio-output-set-default" 42 analog headphones
expected_calls=$'pactl set-sink-port analog headphones\nwpctl set-default 42\npactl set-default-sink analog\npactl move-sink-input 10 analog'
actual_calls=$(cat "$call_log")
[[ $actual_calls == "$expected_calls" ]] || fail "audio selects a port before the sink and moves only application streams" "$actual_calls"
pass "audio selects a port before the sink and moves only application streams"

: >"$call_log"
PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-audio-output-set-default" 42 analog
if grep -q 'set-sink-port' "$call_log"; then
  fail "audio output selection remains compatible with two arguments"
fi
grep -qx 'wpctl set-default 42' "$call_log" || fail "audio output selection remains compatible with two arguments"
pass "audio output selection remains compatible with two arguments"

: >"$call_log"
if PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-audio-output-set-default" 42 analog vanished 2>/dev/null; then
  fail "audio rejects a vanished output port"
fi
[[ ! -s $call_log ]] || fail "audio rejects a vanished output port" "$(cat "$call_log")"
pass "audio rejects a vanished output port before changing the default"
