#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

# Loads the real binding file against a stub Hyprland API, invokes the captured
# callback, and prints the chord it dispatched for the given focused window.
chord_for() {
  local keys="$1" class="${2:-}"

  OMARCHY_PATH="$ROOT" OMARCHY_TEST_KEYS="$keys" OMARCHY_TEST_CLASS="$class" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local bindings = {}
local sent = {}

hl = {
  dsp = {
    send_key_state = function(spec)
      return spec
    end,
    exec_cmd = function(command)
      return { kind = "exec", arg = command }
    end,
  },
  bind = function(keys, dispatcher)
    bindings[keys] = dispatcher
  end,
  dispatch = function(spec)
    -- The binding splits every chord into a down and an up event; the down
    -- event alone identifies which chord was chosen.
    if type(spec) == "table" and spec.state == "down" then
      sent[#sent + 1] = spec.mods .. " " .. spec.key
    end
  end,
  timer = function() end,
  get_active_window = function()
    local class = os.getenv("OMARCHY_TEST_CLASS")
    if class == nil or class == "" then
      return nil
    end

    return { class = class }
  end,
}

require("default.hypr.helpers")
require("default.hypr.bindings.clipboard")

local keys = os.getenv("OMARCHY_TEST_KEYS")
local dispatcher = bindings[keys]
assert(type(dispatcher) == "function", "no callback bound to " .. keys)
dispatcher()

print(sent[1] or "")
LUA
}

assert_chord() {
  local keys="$1" class="$2" expected="$3" description="$4"
  local actual

  actual=$(chord_for "$keys" "$class")
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected
actual:   $actual"
  pass "$description"
}

assert_chord "SUPER + C" "foot" "CTRL Insert" "universal copy uses the terminal chord in a terminal"
assert_chord "SUPER + C" "google-chrome" "CTRL C" "universal copy uses the GUI chord in an app"
assert_chord "SUPER + C" "" "CTRL C" "universal copy falls back to the GUI chord with no focused window"

# Omarchy's TUIs are terminals carrying an "org.omarchy.<command>" app-id, so
# the GUI chord reaches them as SIGINT and closes the window instead of copying.
assert_chord "SUPER + C" "org.omarchy.btop" "CTRL Insert" "universal copy treats an Omarchy TUI as a terminal"
assert_chord "SUPER + C" "org.omarchy.terminal" "CTRL Insert" "universal copy treats the presentation terminal as a terminal"
assert_chord "SUPER + V" "org.omarchy.btop" "SHIFT Insert" "universal paste treats an Omarchy TUI as a terminal"

# system.lua tags this app-id as a floating window, so it reaches the bindings.
assert_chord "SUPER + C" "org.codeberg.dnkl.foot" "CTRL Insert" "universal copy recognises foot's reverse-DNS app-id"
