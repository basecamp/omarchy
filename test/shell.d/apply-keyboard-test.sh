#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

source "$ROOT/install/provisioning/setup-form.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

resolved_input() {
  OMARCHY_PATH="$ROOT" OMARCHY_VCONSOLE="${1-}" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local vconsole = os.getenv("OMARCHY_VCONSOLE")
local real_open = io.open

io.open = function(path, mode)
  if path ~= "/etc/vconsole.conf" then
    return real_open(path, mode)
  end

  if not vconsole then
    return nil
  end

  local file = io.tmpfile()
  file:write(vconsole)
  file:seek("set")
  return file
end

hl = {
  config = function(config)
    local input = config.input
    print(("[%s] [%s] [%s]"):format(input.kb_layout, input.kb_variant, input.kb_options))
  end,
}

o = { window = function() end }

require("default.hypr.input")
LUA
}

toggle_options="compose:caps,shift:both_capslock_cancel,grp:alts_toggle"
owner="$ROOT/bin/omarchy-provision-owner"

# The original persist path must still be in apply_keyboard. Thai only adds a
# branch in front; it must not replace loadkeys / systemd-firstboot / localectl.
grep -q 'loadkeys "$keymap"' "$owner" || fail "apply_keyboard still loadkeys the chosen console map"
grep -q 'systemd-firstboot --keymap="$keymap" --force' "$owner" ||
  fail "apply_keyboard still persists known console maps with systemd-firstboot"
grep -q 'localectl set-keymap "$keymap"' "$owner" ||
  fail "apply_keyboard still falls back to localectl set-keymap"
grep -q 'keeping the default' "$owner" ||
  fail "apply_keyboard still keeps the default for unknown console maps"
pass "apply_keyboard keeps the existing console persist path"

grep -q 'omarchy_xkb_only_layout "$keymap"' "$owner" ||
  fail "apply_keyboard special-cases XKB-only picker values"
grep -q 'apply_keyboard us' "$owner" ||
  fail "XKB-only layouts reuse apply_keyboard us for the Latin console"
grep -q 'omarchy_write_xkblayout "$keymap"' "$owner" ||
  fail "XKB-only layouts then write XKBLAYOUT via the shared helper"
pass "Thai persist is an added branch, not a replacement of apply_keyboard"

# After apply_keyboard us, vconsole has KEYMAP=us and XKBLAYOUT=us. The new
# helper only rewrites XKBLAYOUT; that is the first-boot Thai step.
vconsole="$tmp_dir/vconsole.conf"
printf '%s\n' 'KEYMAP=us' 'XKBLAYOUT=us' 'FONT=default8x16' >"$vconsole"
omarchy_write_xkblayout th "$vconsole"
grep -qx 'KEYMAP=us' "$vconsole" || fail "writing XKBLAYOUT leaves KEYMAP=us" "$(<"$vconsole")"
grep -qx 'XKBLAYOUT=th' "$vconsole" || fail "writing XKBLAYOUT sets th" "$(<"$vconsole")"
[[ $(grep -c '^XKBLAYOUT=' "$vconsole") == 1 ]] || fail "a single XKBLAYOUT line remains"
grep -qx 'FONT=default8x16' "$vconsole" || fail "other vconsole lines are left alone"
pass "omarchy_write_xkblayout points XKBLAYOUT at th without touching KEYMAP"

desktop=$(resolved_input "$(<"$vconsole")")
[[ $desktop == "[us,th] [,] [$toggle_options]" ]] ||
  fail "Hyprland duals Thai from the first-boot vconsole" "expected: [us,th] [,] [$toggle_options]
actual:   $desktop"
pass "first-boot Thai vconsole becomes a us,th Hyprland session"

missing="$tmp_dir/missing.conf"
printf '%s\n' 'KEYMAP=us' >"$missing"
omarchy_write_xkblayout th "$missing"
grep -qx 'XKBLAYOUT=th' "$missing" || fail "helper appends XKBLAYOUT when the key is absent"
pass "omarchy_write_xkblayout appends XKBLAYOUT when it is missing"

printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | grep -qx 'Thai (Kedmanee)|th' ||
  fail "the picker lists Thai (Kedmanee)"
awk -F'|' '
  $1 == "Tajik" { tajik = 1; next }
  $1 == "Thai (Kedmanee)" { if (!tajik) exit 1; thai = 1; next }
  $1 == "Turkish" { if (!thai) exit 1; exit 0 }
  END { exit thai && tajik ? 0 : 1 }
' <<<"$OMARCHY_KEYBOARD_LAYOUTS" ||
  fail "Thai (Kedmanee) sits alphabetically between Tajik and Turkish"
pass "Thai (Kedmanee) is on the shared picker between Tajik and Turkish"
