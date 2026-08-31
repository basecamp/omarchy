#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# The console is sized by the gap underneath it, recomputed from the monitor,
# because a window rule's size would freeze at whatever the screen measured when
# the console first opened. The arithmetic is what keeps it half a screen on a
# scaled display, so it is worth pinning down.
# base-test.sh does not set -e, so the assertions have to fail the file
# themselves rather than leaving the pass below to run regardless.
OMARCHY_PATH="$ROOT" lua - <<'LUA' || fail "the console covers half the work area at any monitor scale"
local rules, handlers = {}, {}
local monitor = nil

hl = {
  config = function() end,
  animation = function() end,
  workspace_rule = function(rule) table.insert(rules, rule) end,
  on = function(event, callback) handlers[event] = callback end,
  get_active_monitor = function() return monitor end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.qconsole")

local function current()
  return rules[#rules]
end

-- Config loads before the outputs are up, so the first pass has no monitor to
-- read. It still has to leave a rule behind, or the console would open unseeded.
assert(#rules > 0, "console is ruled even before a monitor can be read")
assert(current().on_created_empty:find("omarchy%-agent"), "console is seeded with the default agent")
assert(current().on_created_empty:find("^%[workspace special:scratchpad silent%]"),
  "the seed is pinned to the console rather than trusting the spawn to inherit it")
assert(current().workspace == "special:scratchpad")

local function rescale(height, scale, bar)
  monitor = { height = height, scale = scale, reserved = { top = bar, bottom = 0, left = 0, right = 0 } }
  handlers["monitor.layout_changed"]()
  return current().gaps_out.bottom
end

-- Same panel, same logical size, different scale: the console must not care.
assert(rescale(1080, 1, 40) == 520, "half of a 1080p work area, unscaled")
assert(rescale(2160, 2, 40) == 520, "the same half once the monitor is scaled 2x")
assert(rescale(2160, 1.5, 40) == 700, "and at a fractional scale")

-- The bar is already out of the work area; counting it twice would push the
-- console short.
assert(rescale(1440, 1, 0) == 720, "a monitor with nothing reserved")

-- The console stays flush with the top and the sides, the way a Quake console
-- drops in, and keeps its seed across every refit.
local final = current()
assert(final.gaps_out.top == 0 and final.gaps_out.left == 0 and final.gaps_out.right == 0,
  "the console is flush to the top and sides")
assert(final.on_created_empty:find("omarchy%-agent"), "refitting keeps the console seeded")
assert(final.no_border == true, "the console drops the active window border")

-- A monitor that cannot be read must not wipe the last good rule.
local before = current().gaps_out.bottom
monitor = nil
handlers["monitor.layout_changed"]()
assert(current().gaps_out.bottom == before, "an absent monitor leaves the console as it was")

-- A monitor handle outliving its output answers nil to everything, which is
-- what a layout change looks like mid-flight. Reading height or reserved off
-- that would throw, so the scale guard has to catch it first.
monitor = setmetatable({}, { __index = function() return nil end })
handlers["monitor.layout_changed"]()
assert(current().gaps_out.bottom == before, "an expired monitor handle is not read to pieces")

-- Refitting to the size it already is would still cost a state refresh, and
-- monitor.focused fires on every hop between screens.
monitor = { height = 1440, scale = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
local written = #rules
handlers["monitor.focused"]()
handlers["monitor.layout_changed"]()
assert(#rules == written, "refitting to the same size does not rewrite the rule")

monitor.scale = 2
handlers["monitor.layout_changed"]()
assert(#rules == written + 1, "a real change still rewrites it")
assert(current().gaps_out.bottom == 360, "and lands on half the rescaled screen")
LUA
pass "the console covers half the work area at any monitor scale"
