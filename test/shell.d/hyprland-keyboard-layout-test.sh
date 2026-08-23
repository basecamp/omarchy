#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

resolved_input() {
  local mode="${2-desktop}"
  OMARCHY_PATH="$ROOT" OMARCHY_VCONSOLE="${1-}" OMARCHY_ULTIMATE_MODE="$mode" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local vconsole = os.getenv("OMARCHY_VCONSOLE")
if vconsole == "" then
  vconsole = nil
end
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

assert_input() {
  local description="$1"
  local expected="$2"
  local actual

  if (( $# > 2 )); then
    actual=$(resolved_input "$3" "${4-desktop}")
  else
    actual=$(resolved_input "" "desktop")
  fi

  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

power_options="compose:caps,shift:both_capslock_cancel"
power_toggle="$power_options,grp:alts_toggle"

assert_input "Desktop Mode missing vconsole.conf falls back to us without compose-on-caps" "[us] [] []"
assert_input "Desktop Mode us layout keeps Caps Lock" "[us] [intl] []" 'XKBLAYOUT=us
XKBVARIANT=intl
' desktop
assert_input "Desktop Mode latin layouts are left alone" "[de] [nodeadkeys] []" 'XKBLAYOUT=de
XKBVARIANT=nodeadkeys
' desktop
assert_input "Desktop Mode non-latin layout gains us in front" "[us,ara] [,] [grp:alts_toggle]" 'XKBLAYOUT=ara
' desktop
assert_input "Power User Mode missing vconsole.conf uses CapsLock compose" "[us] [] [$power_options]" "" power-user
assert_input "Power User Mode us layout uses CapsLock compose" "[us] [intl] [$power_options]" 'XKBLAYOUT=us
XKBVARIANT=intl
' power-user
assert_input "Power User Mode non-latin layout keeps compose and layout toggle" "[us,ara] [,] [$power_toggle]" 'XKBLAYOUT=ara
' power-user
assert_input "prepended us keeps variants aligned" "[us,ru] [,phonetic] [grp:alts_toggle]" 'XKBLAYOUT=ru
XKBVARIANT=phonetic
' desktop
assert_input "non-latin layout in front gains us even when us trails" "[us,il,us] [,] [grp:alts_toggle]" 'XKBLAYOUT=il,us
' desktop

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
input_lua="$ROOT/default/hypr/input.lua"

hooks_layouts=$(awk -F')' '/\) ;;$/ { gsub(/[[:space:]|]+/, "\n", $1); print $1 }' "$hooks_conf" | grep '^[a-z]\+$' | sort)
lua_layouts=$(sed -n '/^local non_latin_layouts =/,+1p' "$input_lua" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep '^[a-z]\+$' | sort)

[[ -n $hooks_layouts ]] || fail "non-latin layout list is readable from omarchy_hooks.conf"
[[ $hooks_layouts == "$lua_layouts" ]] ||
  fail "non-latin layout lists stay in sync" "$(diff <(echo "$hooks_layouts") <(echo "$lua_layouts"))"
pass "non-latin layout lists stay in sync with the initramfs hook"
