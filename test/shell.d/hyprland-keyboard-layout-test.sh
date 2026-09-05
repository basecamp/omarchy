#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# The session and the greeter are separate Hyprland instances that must resolve
# the same layout, so both are driven through the same stubbed vconsole.conf.
lua_stub() {
  cat <<'LUA'
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
LUA
}

resolved_input() {
  OMARCHY_PATH="$ROOT" OMARCHY_VCONSOLE="${1-}" lua -e "$(lua_stub)" \
    -e 'package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path' \
    -e 'require("default.hypr.input")'
}

# Loaded the way SDDM loads it: by path, with no module path set up for it.
resolved_greeter() {
  OMARCHY_PATH="$ROOT" OMARCHY_VCONSOLE="${1-}" lua -e "$(lua_stub)" \
    -e 'dofile(os.getenv("OMARCHY_PATH") .. "/default/sddm/hyprland.lua")'
}

assert_resolved() {
  local resolver="$1"
  local description="$2"
  local expected="$3"
  local actual

  if (( $# > 3 )); then
    actual=$("$resolver" "$4")
  else
    actual=$("$resolver")
  fi

  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

assert_input() {
  assert_resolved resolved_input "$@"
}

assert_greeter() {
  assert_resolved resolved_greeter "$@"
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

# A greeter left on Hyprland's built-in "us" default makes a password set under
# any other layout untypeable at the login prompt.
assert_greeter "greeter falls back to us without vconsole.conf" "[us] [] [$base_options]"
assert_greeter "greeter follows the system layout" "[be] [] [$base_options]" 'XKBLAYOUT=be
'
assert_greeter "greeter keeps the variant" "[de] [nodeadkeys] [$base_options]" 'XKBLAYOUT=de
XKBVARIANT=nodeadkeys
'
assert_greeter "greeter keeps a latin layout reachable for passwords" "[us,ru] [,] [$toggle_options]" 'XKBLAYOUT=ru
'

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
keyboard_lua="$ROOT/default/hypr/keyboard.lua"

hooks_layouts=$(awk -F')' '/\) ;;$/ { gsub(/[[:space:]|]+/, "\n", $1); print $1 }' "$hooks_conf" | grep '^[a-z]\+$' | sort)
lua_layouts=$(sed -n '/^local non_latin_layouts =/,+1p' "$keyboard_lua" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep '^[a-z]\+$' | sort)

[[ -n $hooks_layouts ]] || fail "non-latin layout list is readable from omarchy_hooks.conf"
[[ $hooks_layouts == "$lua_layouts" ]] ||
  fail "non-latin layout lists stay in sync" "$(diff <(echo "$hooks_layouts") <(echo "$lua_layouts"))"
pass "non-latin layout lists stay in sync with the initramfs hook"
