#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# The console is sized by the gaps around it, recomputed from the monitor,
# because a window rule's size would freeze at whatever the screen measured when
# the console first opened. The arithmetic is what keeps it a half-height panel
# on a scaled display, so it is worth pinning down.
# base-test.sh does not set -e, so the assertions have to fail the file
# themselves rather than leaving the pass below to run regardless.
OMARCHY_PATH="$ROOT" lua - <<'LUA' || fail "the console is a centered panel until a second app joins it"
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
  monitor = { width = 1920, height = height, scale = scale, transform = 0, reserved = { top = bar, bottom = 0, left = 0, right = 0 } }
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

local final = current()
assert(final.gaps_out.top == 0, "the console stays flush with the top, the way a drop-down arrives")
assert(final.gaps_out.left == final.gaps_out.right, "the panel is centered")
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
local expired = setmetatable({}, { __index = function() return nil end })
monitor = expired
handlers["monitor.layout_changed"]()
assert(current().gaps_out.bottom == before, "an expired monitor handle is not read to pieces")

-- Refitting to the size it already is would still cost a state refresh, and
-- monitor.focused fires on every hop between screens.
monitor = { width = 2560, height = 1440, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
local written = #rules
handlers["monitor.focused"]()
handlers["monitor.layout_changed"]()
assert(#rules == written, "refitting to the same size does not rewrite the rule")

-- A centered 2:1 panel, not a full-width drop-down.
monitor = { width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
local top, right, bottom, left = gaps()
assert(top == 0 and left == 420 and right == 420 and bottom == 540, "16:9 leaves a 1080x540 panel")

local dell = { name = "DP-1", width = 6144, height = 2560, scale = 1, transform = 0, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
monitor = dell
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 1807 and right == 1807 and bottom == 1265, "the same 2:1 panel on 6K")

-- Same logical box at scale 2x (physical 12288x5120): scale does not change the
-- panel's logical size.
monitor = { name = "DP-1", width = 12288, height = 5120, scale = 2, transform = 0, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 1807 and right == 1807 and bottom == 1265, "the 6K box is in logical pixels")

-- Same height, different width: the sides have to move even though the bottom
-- gap is identical, so the cache cannot key on height alone.
monitor = { width = 2560, height = 1440, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
written = #rules
monitor = { width = 3440, height = 1440, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
assert(#rules == written + 1, "a same-height ultrawide hop still rewrites the sides")
top, right, bottom, left = gaps()
assert(left == 1000 and right == 1000 and bottom == 720, "3440x1440 leaves a 1440x720 box")

-- A panel wider than the screen is just the screen: a portrait monitor has no
-- room for a 2:1 box and falls back to the full width rather than a negative gap.
monitor = { width = 1080, height = 1920, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 0 and right == 0 and bottom == 960, "a portrait monitor keeps the full width")
assert(left >= 0 and right >= 0 and bottom >= 0, "gaps are never negative")

-- A monitor turned on its side still reports the panel's own pixels, so the
-- work area has to be turned with it. Measured against Hyprland 0.56.2: a
-- rotated 1920x1080 lays its windows out in 1080x1920 while width and height
-- still read 1920 and 1080. Quarter turns are the odd transforms; a half turn
-- leaves the shape alone.
monitor = { width = 1920, height = 1080, scale = 1, transform = 1, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 0 and right == 0 and bottom == 945, "a quarter-turned monitor is sized portrait")

monitor = { width = 1920, height = 1080, scale = 1, transform = 3, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 0 and right == 0 and bottom == 945, "and so is the other quarter turn")

monitor = { width = 1920, height = 1080, scale = 1, transform = 2, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 435 and right == 435 and bottom == 525, "a half turn is still landscape")

-- Special workspaces open on the monitor they are toggled on, not on whichever
-- output was focused when the rule was last written. Opening on 1080p after a
-- 6K fit has to resize the box.
local acer = { name = "HDMI-A-1", width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
monitor = dell
handlers["monitor.layout_changed"]()
handlers["workspace.special_active"]({ name = "special:scratchpad" }, acer)
top, right, bottom, left = gaps()
assert(left == 435 and right == 435 and bottom == 525, "opening on 1080p after a 6K fit resizes the box")
assert(1920 - left - right > 0 and 1080 - 30 - bottom > 0, "1080p leftover is never negative")

-- follow_mouse onto the 6K while the console is already showing on 1080p must
-- not steal the rule; that is what oversized the Dell after a hop.
workspace = { name = "special:scratchpad", visible = true, monitor = acer, windows = 1 }
monitor = dell
written = #rules
handlers["monitor.focused"](dell)
assert(#rules == written, "focus on another output does not rewrite an open console")

-- The output the console is showing on can go away mid-layout-change. Its
-- handle then answers nil to everything, and preferring it blindly would leave
-- the console stranded at the gaps of the monitor that is gone. The rule is
-- still the 1080p one here, so only refitting on the Dell can satisfy this.
workspace = { name = "special:scratchpad", visible = true, monitor = expired, windows = 1 }
monitor = dell
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 1807 and right == 1807 and bottom == 1265,
  "a console whose output vanished refits on the monitor that is still there")

-- Back onto the 1080p panel for the window-count checks below.
workspace = { name = "special:scratchpad", visible = true, monitor = acer, windows = 1 }
monitor = acer
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 435 and right == 435 and bottom == 525, "and refits again once it is back on a live output")

-- One window reads as a console and keeps the panel. A second app has turned
-- the scratchpad into a workspace, and a workspace wants the whole width.
workspace = { name = "special:scratchpad", visible = true, monitor = acer, windows = 2 }
handlers["window.open"]()
top, right, bottom, left = gaps()
assert(left == 0 and right == 0, "a second app on the scratchpad restores the full width")
assert(bottom == 525, "and the console keeps its half-height drop")

workspace.windows = 3
written = #rules
handlers["window.open"]()
assert(#rules == written, "a third app changes nothing that is already full width")

workspace.windows = 1
handlers["window.destroy"]()
top, right, bottom, left = gaps()
assert(left == 435 and right == 435, "closing back down to one window recenters the panel")

-- An empty scratchpad is about to be seeded with a single agent, so it is sized
-- as a console rather than as a workspace.
workspace.windows = 0
handlers["window.destroy"]()
top, right, bottom, left = gaps()
assert(left == 435 and right == 435, "an empty console is still a console")

-- A hidden console is refitted on its way back in, so the count does not have to
-- be chased while it is off screen; every window on the desktop would otherwise
-- rewrite the rule.
workspace = { name = "special:scratchpad", visible = false, monitor = acer, windows = 4 }
monitor = dell
written = #rules
handlers["window.open"]()
assert(#rules == written, "a window opening elsewhere does not rewrite a hidden console")

-- A scratchpad nothing has opened yet has no workspace to read at all, and is
-- sized as the console the seed is about to put a single agent into.
workspace = nil
monitor = { width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
handlers["monitor.layout_changed"]()
top, right, bottom, left = gaps()
assert(left == 420 and right == 420 and bottom == 540, "a scratchpad that does not exist yet is sized as a console")

-- window.close and window.move_to_workspace both run while the workspace still
-- counts the window that is leaving, so a refit from either reads one too many
-- and strands the console at full width. window.open and window.destroy are the
-- two that run after the count has already moved, and are the only ones hooked.
assert(handlers["window.close"] == nil, "window.close counts the window on its way out")
assert(handlers["window.move_to_workspace"] == nil, "window.move_to_workspace does too")
LUA
pass "the console is a centered panel until a second app joins it"
