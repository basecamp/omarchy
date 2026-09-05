#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

touchpad="$ROOT/bin/omarchy-hw-touchpad"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Hyprland names the internal trackpad after its MTP HID interface on Apple
# Silicon, so the device the input-device toggle gates on says neither
# touchpad nor trackpad there.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

jq -n --arg name "${MOUSE_NAME:-}" \
  '{mice: (if $name == "" then [] else [{name: $name}] end), keyboards: []}'
SH

chmod +x "$stub_bin"/*

detected() {
  MOUSE_NAME="$1" PATH="$stub_bin:$PATH" bash "$touchpad"
}

[[ $(detected "apple-mtp-multi-touch") == "apple-mtp-multi-touch" ]] ||
  fail "the Apple Silicon trackpad is detected" "$(detected "apple-mtp-multi-touch")"
pass "the Apple Silicon trackpad is detected"

# omarchy-toggle-input-device passes the name straight to hl.device, so a name
# that does not match leaves the menu entry hidden and the toggle dead.
for name in "elan-touchpad" "apple-magic-trackpad-2"; do
  [[ $(detected "$name") == "$name" ]] || fail "the touchpads that already worked still do" "$(detected "$name")"
done
pass "the touchpads that already worked still do"

[[ -z $(detected "logitech-mx-master-3") ]] ||
  fail "an ordinary mouse is not mistaken for a touchpad" "$(detected "logitech-mx-master-3")"
pass "an ordinary mouse is not mistaken for a touchpad"

[[ -z $(detected "") ]] ||
  fail "no touchpad answers with an empty detection" "$(detected "")"
pass "no touchpad answers with an empty detection"
