#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ ${1:-} == devices && ${2:-} == -j ]]; then
  cat "$TEST_DEVICES_JSON"
  exit 0
fi
exit 1
SH
chmod +x "$stub_bin/hyprctl"

run_detect() {
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-hw-touchpad"
}

export TEST_DEVICES_JSON="$test_tmp/devices.json"

# Classic name still works.
cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[{"name":"elan-touchpad"},{"name":"logitech-usb-mouse"}],"touch":[]}
JSON
[[ $(run_detect) == "elan-touchpad" ]] || fail "detects *touchpad* names" "$(run_detect)"
pass "detects *touchpad* names"

# Vendor/controller name with no touchpad substring (#9805).
cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[{"name":"synaptics-tm3096-006"},{"name":"logitech-g502"}],"touch":[]}
JSON
[[ $(run_detect) == "synaptics-tm3096-006" ]] ||
  fail "detects synaptics controller touchpads" "$(run_detect)"
pass "detects synaptics controller touchpads"

cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[{"name":"alps-1013"},{"name":"usb-mouse"}],"touch":[]}
JSON
[[ $(run_detect) == "alps-1013" ]] || fail "detects alps touchpads" "$(run_detect)"
pass "detects alps touchpads"

# Prefer touchpad-named device over a later vendor match.
cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[{"name":"synaptics-other"},{"name":"asup1205:00-1043:18a3-touchpad"}],"touch":[]}
JSON
[[ $(run_detect) == "asup1205:00-1043:18a3-touchpad" ]] ||
  fail "prefers an explicit touchpad name when present" "$(run_detect)"
pass "prefers an explicit touchpad name when present"

# No false positive on plain USB mice only.
cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[{"name":"logitech-usb-receiver"},{"name":"razer-deathadder"}],"touch":[{"name":"wacom-touchscreen"}]}
JSON
out=$(run_detect)
[[ -z $out ]] || fail "ignores plain mice and touchscreens" "got: $out"
pass "ignores plain mice and touchscreens"

# Empty devices.
cat >"$TEST_DEVICES_JSON" <<'JSON'
{"mice":[],"touch":[]}
JSON
[[ -z $(run_detect) ]] || fail "empty device list yields no name"
pass "empty device list yields no name"
