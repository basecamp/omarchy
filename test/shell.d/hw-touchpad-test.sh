#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_dir="$tmp_dir/bin"
input_dir="$tmp_dir/input"
udev_dir="$tmp_dir/udev"
hypr_json="$tmp_dir/devices.json"
mkdir -p "$stub_dir" "$input_dir" "$udev_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash
if [[ $1 == "devices" && $2 == "-j" ]]; then
  cat "$HYPR_DEVICES_JSON"
  exit 0
fi
exit 1
EOF

cat >"$stub_dir/udevadm" <<'EOF'
#!/bin/bash
path=${*: -1}
base=${path##*/}
props="$UDEVADM_PROPS_DIR/$base"
[[ -f $props ]] || exit 1
cat "$props"
EOF

chmod +x "$stub_dir"/*

write_hypr_mice() {
  local name
  local names=()
  for name in "$@"; do
    names+=("$(printf '{"name":"%s"}' "$name")")
  done

  local joined
  joined=$(IFS=,; printf '%s' "${names[*]}")
  printf '{"mice":[%s]}\n' "$joined" >"$hypr_json"
}

add_event() {
  local event=$1 name=$2
  shift 2
  mkdir -p "$input_dir/$event/device"
  printf '%s\n' "$name" >"$input_dir/$event/device/name"
  printf '%s\n' "$@" >"$udev_dir/$event"
}

hw_touchpad() {
  PATH="$stub_dir:$PATH" \
    OMARCHY_INPUT_CLASS_PATH="$input_dir" \
    UDEVADM_PROPS_DIR="$udev_dir" \
    HYPR_DEVICES_JSON="$hypr_json" \
    "$ROOT/bin/omarchy-hw-touchpad"
}

assert_detects() {
  local expected=$1
  local description=$2
  local actual

  actual=$(hw_touchpad) || fail "$description" "expected $expected, command failed"
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

assert_rejects() {
  local description=$1

  if hw_touchpad >/dev/null; then
    fail "$description"
  fi
  pass "$description"
}

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice elan-touchpad 'tpps/2-ibm-trackpoint'
assert_detects elan-touchpad "a device named touchpad is detected without udev"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice 'synaptics-tm3053-004' 'tpps/2-ibm-trackpoint'
add_event event14 'Synaptics TM3053-004' \
  'ID_INPUT=1' \
  'ID_INPUT_TOUCHPAD=1' \
  'ID_INPUT_TOUCHPAD_INTEGRATION=internal'
add_event event15 'TPPS/2 IBM TrackPoint' \
  'ID_INPUT=1' \
  'ID_INPUT_MOUSE=1' \
  'ID_INPUT_POINTINGSTICK=1'
assert_detects 'synaptics-tm3053-004' "a ThinkPad Synaptics pad is detected by udev type"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice elan-touchpad 'synaptics-tm3053-004'
add_event event14 'Synaptics TM3053-004' \
  'ID_INPUT=1' \
  'ID_INPUT_TOUCHPAD=1'
assert_detects elan-touchpad "the name match wins over a udev-only pad"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice 'synaptics-tm3053-004-1'
add_event event14 'Synaptics TM3053-004' \
  'ID_INPUT=1' \
  'ID_INPUT_TOUCHPAD=1'
assert_detects 'synaptics-tm3053-004-1' "a Hyprland duplicate-name suffix still matches"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice 'tpps/2-ibm-trackpoint' 'e-signal-dm360'
add_event event15 'TPPS/2 IBM TrackPoint' \
  'ID_INPUT=1' \
  'ID_INPUT_MOUSE=1' \
  'ID_INPUT_POINTINGSTICK=1'
add_event event5 'E-Signal DM360' \
  'ID_INPUT=1' \
  'ID_INPUT_MOUSE=1' \
  'ID_BUS=usb'
assert_rejects "a TrackPoint and USB mouse are not treated as a touchpad"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice 'synaptics-tm3053-004'
add_event event14 'Synaptics TM3053-004' \
  'ID_INPUT=1' \
  'ID_INPUT_TOUCHPAD=1' \
  'ID_INPUT_POINTINGSTICK=1'
assert_rejects "a pointing stick tagged as a touchpad is skipped"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice 'e-signal-dm360'
add_event event14 'Synaptics TM3053-004' \
  'ID_INPUT=1' \
  'ID_INPUT_TOUCHPAD=1'
assert_rejects "a udev touchpad that Hyprland does not list is ignored"

rm -rf "$input_dir" "$udev_dir"
mkdir -p "$input_dir" "$udev_dir"
write_hypr_mice
assert_rejects "no pointer devices reports failure"
