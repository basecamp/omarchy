#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua
require_command systemd-firstboot
require_command localectl

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

vconsole_lines() {
  grep -E '^(KEYMAP|XKBLAYOUT)=' "$1/etc/vconsole.conf"
}

make_root() {
  local root=$1
  mkdir -p "$root/etc"
  printf '%s\n' 'KEYMAP=us' 'FONT=default8x16' >"$root/etc/vconsole.conf"
}

toggle_options="compose:caps,shift:both_capslock_cancel,grp:alts_toggle"

# First-boot persist is the shipped omarchy_apply_keyboard: real systemd-firstboot
# --root, then the XKBLAYOUT overwrite for xkb-only picker values.

thai_root="$tmp_dir/thai"
make_root "$thai_root"
omarchy_apply_keyboard th "$thai_root" || fail "omarchy_apply_keyboard persists Thai"
vconsole_lines "$thai_root" | grep -qx 'KEYMAP=us' ||
  fail "Thai keeps a US console keymap" "$(vconsole_lines "$thai_root")"
vconsole_lines "$thai_root" | grep -qx 'XKBLAYOUT=th' ||
  fail "Thai writes XKBLAYOUT=th for Hyprland" "$(vconsole_lines "$thai_root")"
[[ $(grep -c '^XKBLAYOUT=' "$thai_root/etc/vconsole.conf") == 1 ]] ||
  fail "Thai leaves a single XKBLAYOUT line"
pass "omarchy_apply_keyboard persists Thai as KEYMAP=us XKBLAYOUT=th"

desktop=$(resolved_input "$(<"$thai_root/etc/vconsole.conf")")
[[ $desktop == "[us,th] [,] [$toggle_options]" ]] ||
  fail "Hyprland duals Thai from the persisted vconsole" "expected: [us,th] [,] [$toggle_options]
actual:   $desktop"
pass "persisted Thai vconsole becomes a us,th Hyprland session"

de_root="$tmp_dir/de"
make_root "$de_root"
omarchy_apply_keyboard de "$de_root" || fail "omarchy_apply_keyboard persists German"
vconsole_lines "$de_root" | grep -qx 'KEYMAP=de' ||
  fail "German still writes KEYMAP=de" "$(vconsole_lines "$de_root")"
vconsole_lines "$de_root" | grep -qx 'XKBLAYOUT=de' ||
  fail "German still writes XKBLAYOUT=de" "$(vconsole_lines "$de_root")"
pass "omarchy_apply_keyboard leaves console keymaps on themselves"

unknown_root="$tmp_dir/unknown"
make_root "$unknown_root"
before=$(<"$unknown_root/etc/vconsole.conf")
if omarchy_apply_keyboard definitely-not-a-keymap "$unknown_root"; then
  fail "unknown picker values must not persist"
fi
[[ $(<"$unknown_root/etc/vconsole.conf") == "$before" ]] ||
  fail "unknown picker values leave vconsole.conf untouched"
pass "unknown layouts are refused without rewriting vconsole.conf"

grep -q 'omarchy_apply_keyboard "\$1"' "$ROOT/bin/omarchy-provision-owner" ||
  fail "first-boot apply_keyboard calls the shared persist helper"
pass "omarchy-provision-owner apply_keyboard uses omarchy_apply_keyboard"

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
