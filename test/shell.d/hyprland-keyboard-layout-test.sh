#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

resolved_input_for() {
  local module="$1"
  OMARCHY_PATH="$ROOT" OMARCHY_MODULE="$module" OMARCHY_VCONSOLE="${2-}" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local vconsole = os.getenv("OMARCHY_VCONSOLE")
local real_open = io.open

io.open = function(path, mode)
  if path ~= "/etc/vconsole.conf" then
    return real_open(path, mode)
  end

  -- An unset OMARCHY_VCONSOLE reaches Lua as "", never nil, so the cases that
  -- ask for a missing /etc/vconsole.conf need the empty string to fail the open.
  if not vconsole or vconsole == "" then
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

require(os.getenv("OMARCHY_MODULE"))
LUA
}

resolved_input() {
  resolved_input_for "default.hypr.input" "${1-}"
}

# The greeter compositor resolves the layout from its own entrypoint.
resolved_greeter_input() {
  resolved_input_for "default.sddm.hyprland" "${1-}"
}

assert_resolved_input() {
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
  assert_resolved_input resolved_input "$@"
}

assert_greeter_input() {
  assert_resolved_input resolved_greeter_input "$@"
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

# The greeter takes no compose or capslock options: they're session comfort
# settings with nothing to do with typing a password.
assert_greeter_input "greeter falls back to us without vconsole.conf" "[us] [] []"

assert_greeter_input "greeter follows the system layout" "[fr] [] []" 'XKBLAYOUT=fr
'

assert_greeter_input "greeter keeps a latin layout in front" "[us,ru] [,phonetic] [grp:alts_toggle]" 'XKBLAYOUT=ru
XKBVARIANT=phonetic
'

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
input_lua="$ROOT/default/hypr/input.lua"

hooks_layouts=$(awk -F')' '/\) ;;$/ { gsub(/[[:space:]|]+/, "\n", $1); print $1 }' "$hooks_conf" | grep '^[a-z]\+$' | sort)
lua_layouts=$(sed -n '/^local non_latin_layouts =/,+1p' "$input_lua" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep '^[a-z]\+$' | sort)

[[ -n $hooks_layouts ]] || fail "non-latin layout list is readable from omarchy_hooks.conf"

[[ $hooks_layouts == "$lua_layouts" ]] ||
  fail "non-latin layout lists stay in sync" "$(diff <(echo "$hooks_layouts") <(echo "$lua_layouts"))"
pass "non-latin layout lists stay in sync with the initramfs hook"

sddm_lua="$ROOT/default/sddm/hyprland.lua"
sddm_layouts=$(sed -n '/^local non_latin_layouts =/,+1p' "$sddm_lua" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep '^[a-z]\+$' | sort)

[[ $hooks_layouts == "$sddm_layouts" ]] ||
  fail "greeter non-latin layout list stays in sync" "$(diff <(echo "$hooks_layouts") <(echo "$sddm_layouts"))"
pass "greeter non-latin layout list stays in sync with the initramfs hook"
