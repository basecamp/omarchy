#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

resolved_input() {
  OMARCHY_PATH="$ROOT" \
    OMARCHY_VCONSOLE="${1-}" \
    OMARCHY_KBD_MODEL_MAP="${2-}" \
    lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local vconsole = os.getenv("OMARCHY_VCONSOLE")
local kbd_model_map = os.getenv("OMARCHY_KBD_MODEL_MAP")
local real_open = io.open

io.open = function(path, mode)
  local contents
  if path == "/etc/vconsole.conf" then
    contents = vconsole
  elseif path == "/usr/share/systemd/kbd-model-map" then
    contents = kbd_model_map
  else
    return real_open(path, mode)
  end

  if not contents or contents == "" then
    return nil
  end

  local file = io.tmpfile()
  file:write(contents)
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

assert_input() {
  local description="$1"
  local expected="$2"
  local actual

  if (( $# > 3 )); then
    actual=$(resolved_input "$3" "$4")
  elif (( $# > 2 )); then
    actual=$(resolved_input "$3")
  else
    actual=$(resolved_input)
  fi

  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

base_options="compose:caps,shift:both_capslock_cancel"
toggle_options="$base_options,grp:alts_toggle"

assert_input "missing vconsole.conf falls back to us" "[us] [] [$base_options]"
assert_input "us layout passes through" "[us] [intl] [$base_options]" 'XKBLAYOUT=us
XKBVARIANT=intl
'
assert_input "latin layouts are left alone" "[de] [nodeadkeys] [$base_options]" 'XKBLAYOUT=de
XKBVARIANT=nodeadkeys
'
assert_input "non-latin layout gains us in front" "[us,ara] [,] [$toggle_options]" 'XKBLAYOUT=ara
'
assert_input "prepended us keeps variants aligned" "[us,ru] [,phonetic] [$toggle_options]" 'XKBLAYOUT=ru
XKBVARIANT=phonetic
'
assert_input "non-latin layout in front gains us even when us trails" "[us,il,us] [,] [$toggle_options]" 'XKBLAYOUT=il,us
'

assert_input "console keymap resolves through systemd's XKB map" "[fr] [] [$base_options]" 'KEYMAP=fr
' 'fr fr pc105 - terminate:ctrl_alt_bksp
'
assert_input "console keymap keeps the variant from systemd's XKB map" "[us] [dvorak] [$base_options]" 'KEYMAP=dvorak
' 'dvorak us pc105 dvorak terminate:ctrl_alt_bksp
'
assert_input "non-latin console keymap resolved through systemd gains us in front" "[us,ru] [,] [$toggle_options]" 'KEYMAP=ru
' 'ru ru pc105 - terminate:ctrl_alt_bksp
'
assert_input "console keymap missing from systemd's map uses Omarchy's fallback" "[us] [colemak] [$base_options]" 'KEYMAP=colemak
' 'us us pc105 - terminate:ctrl_alt_bksp
'
assert_input "explicit XKB settings take precedence over the console keymap" "[de] [nodeadkeys] [$base_options]" 'KEYMAP=colemak
XKBLAYOUT=de
XKBVARIANT=nodeadkeys
'
assert_input "an unknown console keymap still falls back to us" "[us] [] [$base_options]" 'KEYMAP=definitely-not-a-keymap
'

while IFS='|' read -r keymap expected; do
  assert_input "installer keymap $keymap has an XKB fallback" "$expected" "KEYMAP=$keymap"$'\n'
done <<EOF
colemak|[us] [colemak] [$base_options]
azerty|[az] [] [$base_options]
bg-cp1251|[us,bg] [,] [$toggle_options]
cz|[cz] [] [$base_options]
de_CH-latin1|[ch] [] [$base_options]
kyrgyz|[us,kg] [,] [$toggle_options]
no-latin1|[no] [] [$base_options]
pl|[pl] [] [$base_options]
ua|[us,ua] [,] [$toggle_options]
EOF

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
input_lua="$ROOT/default/hypr/input.lua"
setup_form="$ROOT/install/provisioning/setup-form.sh"

if [[ -r /usr/share/systemd/kbd-model-map ]]; then
  source "$setup_form"

  installer_keymaps=$(printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | cut -d'|' -f2 | sort -u)
  model_map_keymaps=$(awk '!/^[[:space:]]*#/ && NF { print $1 }' /usr/share/systemd/kbd-model-map | sort -u)
  fallback_keymaps=$(sed -n '/^local keymap_xkb_fallbacks = {/,/^}/p' "$input_lua" |
    sed -E -n 's/^[[:space:]]*([[:alnum:]_-]+)[[:space:]]*=.*/\1/p; s/^[[:space:]]*\["([^"]+)"\][[:space:]]*=.*/\1/p' |
    sort -u)
  unresolved_keymaps=$(comm -23 <(printf '%s\n' "$installer_keymaps") <(printf '%s\n%s\n' "$model_map_keymaps" "$fallback_keymaps" | sort -u))

  [[ -z $unresolved_keymaps ]] ||
    fail "installer keymaps resolve through systemd or Omarchy's fallback table" "unresolved keymaps:"$'\n'"$unresolved_keymaps"
  pass "installer keymaps resolve through systemd or Omarchy's fallback table"
else
  pass "systemd keyboard map unavailable; skipping installer keymap sync check"
fi

hooks_layouts=$(awk -F')' '/\) ;;$/ { gsub(/[[:space:]|]+/, "\n", $1); print $1 }' "$hooks_conf" | grep '^[a-z]\+$' | sort)
lua_layouts=$(sed -n '/^local non_latin_layouts =/,+1p' "$input_lua" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep '^[a-z]\+$' | sort)

[[ -n $hooks_layouts ]] || fail "non-latin layout list is readable from omarchy_hooks.conf"
[[ $hooks_layouts == "$lua_layouts" ]] ||
  fail "non-latin layout lists stay in sync" "$(diff <(echo "$hooks_layouts") <(echo "$lua_layouts"))"
pass "non-latin layout lists stay in sync with the initramfs hook"
