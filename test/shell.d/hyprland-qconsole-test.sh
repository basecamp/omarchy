#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# The console is sized by the gap underneath it, recomputed from the monitor,
# because a window rule's size would freeze at whatever the screen measured when
# the console first opened. The arithmetic is what keeps it half a screen on a
# scaled display, so it is worth pinning down.
# base-test.sh does not set -e, so the assertions have to fail the file
# themselves rather than leaving the pass below to run regardless.
OMARCHY_PATH="$ROOT" lua - <<'LUA' || fail "the console is a half-height 2:1 panel by default"
local rules, handlers = {}, {}
local monitor = nil
local workspace = nil

hl = {
  config = function() end,
  animation = function() end,
  workspace_rule = function(rule) table.insert(rules, rule) end,
  on = function(event, callback) handlers[event] = callback end,
  get_active_monitor = function() return monitor end,
  get_workspace = function() return workspace end,
  exec_scheduled_prop_refresh_immediately = function() end,
}

-- Same default as config/hypr/hyprland.lua: a centered panel twice as wide as
-- it is tall. Commenting that assignment out is what restores full width.
omarchy_qconsole_ratio = 2

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.qconsole")

local function current()
  return rules[#rules]
end

local function gaps()
  local g = current().gaps_out
  return g.top, g.right, g.bottom, g.left
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
-- These fixtures omit width, so the ratio cannot inset the sides yet.
assert(rescale(1080, 1, 40) == 520, "half of a 1080p work area, unscaled")
assert(rescale(2160, 2, 40) == 520, "the same half once the monitor is scaled 2x")
assert(rescale(2160, 1.5, 40) == 700, "and at a fractional scale")

-- The bar is already out of the work area; counting it twice would push the
-- console short.
assert(rescale(1440, 1, 0) == 720, "a monitor with nothing reserved")

local final = current()
assert(final.gaps_out.top == 0, "the console stays flush with the top")
assert(final.gaps_out.left == 0 and final.gaps_out.right == 0,
  "without a width the sides stay flush")
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

-- Default ratio: 16:9 is a centered 2:1 panel, not a full-width drop-down.
monitor = { width = 1920, height = 1080, scale = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
local top, right, bottom, left = gaps()
assert(top == 0 and left == 420 and right == 420 and bottom == 540, "16:9 default is a 1080x540 panel")

local dell = { name = "DP-1", width = 6144, height = 2560, scale = 1, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
monitor = dell
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 1807 and right == 1807 and bottom == 1265, "the same 2:1 panel on 6K")

-- Same logical box at scale 2x (physical 12288x5120).
-- It checks that scale does not change the panel's logical size.
monitor = { name = "DP-1", width = 12288, height = 5120, scale = 2, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 1807 and right == 1807 and bottom == 1265, "the 6K box is in logical pixels")

-- Acer 1920x1080, bar 30, same ratio. Opening here after a 6K fit must rewrite;
-- leaving 6K side gaps would make leftover width negative.
local acer = { name = "HDMI-A-1", width = 1920, height = 1080, scale = 1, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
monitor = dell
handlers["monitor.layout_changed"]()
handlers["workspace.special_active"]({ name = "special:scratchpad" }, acer)
top, right, bottom, left = gaps()
assert(left == 435 and right == 435 and bottom == 525, "opening on 1080p after a 6K fit resizes the 2:1 box")
assert(1920 - left - right > 0 and 1080 - 30 - bottom > 0, "1080p leftover is never negative")

-- follow_mouse onto the 6K while the console is already showing on 1080p must
-- not steal the global rule (that is what oversized the Dell after a hop).
workspace = { name = "special:scratchpad", visible = true, monitor = acer }
written = #rules
handlers["monitor.focused"](dell)
assert(#rules == written, "focus on another output does not rewrite an open console")
workspace = nil

-- Cache: same 1440p height, 16:9 vs 21:9. Sides change even when bottom does not.
monitor = { width = 2560, height = 1440, scale = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
written = #rules
monitor = { width = 3440, height = 1440, scale = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
assert(#rules == written + 1, "a same-height ultrawide hop still rewrites the sides")
top, right, bottom, left = gaps()
assert(left == 1000 and right == 1000 and bottom == 720, "3440x1440 at ratio 2 is a 2:1 box")

omarchy_qconsole_ratio = 1
monitor = { width = 1920, height = 1080, scale = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 690 and right == 690 and bottom == 540, "ratio 1 is a square")

omarchy_qconsole_ratio = 0.5
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 690 and right == 690 and bottom == 540, "a ratio below 1 clamps to a square")

omarchy_qconsole_ratio = nil
monitor = dell
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 0 and right == 0 and bottom == 1265, "clearing the ratio restores full width")
LUA
pass "the console is a half-height 2:1 panel by default"
