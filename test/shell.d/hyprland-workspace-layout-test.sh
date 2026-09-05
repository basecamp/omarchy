#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir" "$home_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == "activeworkspace" && -n $HYPRCTL_BROKEN ]]; then
  printf '{}\n'
elif [[ $1 == "activeworkspace" ]]; then
  printf '{"id":%s,"tiledLayout":"%s"}\n' "${HYPRCTL_WS_ID:-3}" "${HYPRCTL_TILED_LAYOUT:-dwindle}"
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"

  if [[ $1 == "eval" && -n $HYPRCTL_EVAL_FAILS ]]; then
    exit 7
  fi
fi
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFICATION_LOG"
EOF
chmod +x "$stub_dir/omarchy-notification-send"

layout_file="$home_dir/.local/state/omarchy/workspace-layouts/3.lua"
notification_log="$tmpdir/notifications.log"

# XDG_STATE_HOME is named explicitly rather than left to be inherited: a machine
# that sets it would otherwise have its real saved layouts written over by these
# runs. It is the value the command would derive from this HOME anyway, and a
# case that needs another one passes its own, which env applies last.
toggle() {
  env HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" \
    HYPRCTL_LOG="$log_file" NOTIFICATION_LOG="$notification_log" \
    PATH="$stub_dir:$PATH" "$@" "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle"
}

saved_mode() {
  sed -n 's/.*mode = "\([a-z]*\)".*/\1/p' "$layout_file" 2>/dev/null
}

applied() {
  grep -Fx "eval o.workspace_mode({ workspace = \"3\", mode = \"$1\" })" "$log_file" >/dev/null
}

# Nothing saved yet, so the cycle starts from the layout Hyprland reports.
: >"$notification_log"
toggle
[[ -f $layout_file ]] || fail "workspace layout toggle saves the selected mode"
[[ $(saved_mode) == "scrolling" ]] || fail "dwindle cycles to scrolling" "saved: $(cat "$layout_file")"
applied scrolling || fail "scrolling is applied immediately" "$(cat "$log_file")"
grep -q "set to scrolling" "$notification_log" ||
  fail "the new mode is announced" "$(cat "$notification_log")"
if grep -q "could not be saved" "$notification_log"; then
  fail "a saved mode is announced as saved" "$(cat "$notification_log")"
fi
pass "dwindle cycles to scrolling"

# The saved file is what carries the mode from here: floating is not a tiled
# layout, so Hyprland could never report it back.
toggle
[[ $(saved_mode) == "floating" ]] || fail "scrolling cycles to floating" "saved: $(cat "$layout_file")"
applied floating || fail "floating is applied immediately" "$(cat "$log_file")"
pass "scrolling cycles to floating"

# Hyprland still reports a tiled layout underneath a floating workspace, so a
# toggle that trusted the compositor here would cycle back to scrolling and skip
# dwindle entirely. The apply matters as much as the file: without it the saved
# mode says dwindle while the screen stays floating.
toggle
[[ $(saved_mode) == "dwindle" ]] || fail "floating cycles back to dwindle" "saved: $(cat "$layout_file")"
applied dwindle || fail "dwindle is applied immediately" "$(cat "$log_file")"
pass "floating cycles back to dwindle"

# Files written before floating existed name a layout rather than a mode.
: >"$log_file"
printf 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })\n' >"$layout_file"
toggle HYPRCTL_TILED_LAYOUT=scrolling
[[ $(saved_mode) == "floating" ]] ||
  fail "a saved layout from before floating cycles on into floating" "saved: $(cat "$layout_file")"
applied floating || fail "the mode after a legacy layout is applied" "$(cat "$log_file")"
pass "a saved layout from before floating cycles on into floating"

# A mode that did not apply must not be restored at the next login, and must not
# be announced as though it had been.
printf 'o.workspace_mode({ workspace = "3", mode = "scrolling" })\n' >"$layout_file"
: >"$notification_log"
toggle HYPRCTL_EVAL_FAILS=1
[[ $(saved_mode) == "scrolling" ]] ||
  fail "a mode that failed to apply is not saved" "saved: $(cat "$layout_file")"
grep -q "needs a Hyprland reload" "$notification_log" ||
  fail "a mode that failed to apply says so" "$(cat "$notification_log")"
if grep -q "set to" "$notification_log"; then
  fail "a mode that failed to apply is announced as set" "$(cat "$notification_log")"
fi
pass "a mode that failed to apply is neither saved nor announced as set"

# The mode is on screen but nothing will bring it back, and the next press reads
# the mode from the file that was not written, so it cannot count as set. A
# regular file where the state directory belongs fails mkdir for any user,
# including root.
blocked="$tmpdir/blocked"
printf 'not a directory\n' >"$blocked"
: >"$log_file"
: >"$notification_log"
toggle XDG_STATE_HOME="$blocked" 2>/dev/null
applied scrolling || fail "the mode is still applied when it cannot be saved" "$(cat "$log_file")"
grep -q "could not be saved" "$notification_log" ||
  fail "a mode that could not be saved says so" "$(cat "$notification_log")"
pass "a mode that applied but could not be saved says so"

# A named workspace reports a negative id, and Hyprland reads a leading "-" as a
# selector relative to the current workspace: acting on one reconfigures
# workspace 1 rather than the workspace the user is looking at.
: >"$log_file"
if toggle HYPRCTL_WS_ID=-1337 2>/dev/null; then
  fail "workspace layout toggle exits nonzero on a named workspace"
fi
if grep -q "workspace_mode" "$log_file"; then
  fail "workspace layout toggle applies nothing for a named workspace" "$(cat "$log_file")"
fi
if [[ -f $home_dir/.local/state/omarchy/workspace-layouts/-1337.lua ]]; then
  fail "workspace layout toggle does not persist a mode for a named workspace"
fi
pass "workspace layout toggle leaves a named workspace alone"

# The guard stops new ones being written; the ones an earlier version already
# wrote go on reconfiguring workspace 1 at every login until they are removed.
migration=$(grep -rl 'Drop saved workspace layouts belonging to named workspaces' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "a migration removes saved layouts for named workspaces"

migration_home="$tmpdir/migration"
migration_layouts="$migration_home/.local/state/omarchy/workspace-layouts"
mkdir -p "$migration_layouts"
printf 'o.workspace_mode({ workspace = "-1337", mode = "scrolling" })\n' >"$migration_layouts/-1337.lua"
printf 'o.workspace_mode({ workspace = "3", mode = "scrolling" })\n' >"$migration_layouts/3.lua"

# omarchy-migrate runs each migration as `bash -euo pipefail` and only records it
# as done if it exits 0, so run it the same way here: under those flags an
# unmatched glob is the difference between a migration that finishes and one that
# stops the whole run and repeats it at every login.
# The stub is on the path because the migration asks Hyprland to reload once it
# has removed something, and the real one would reload the compositor of whoever
# is running the suite.
run_migration() {
  env HOME="$migration_home" XDG_STATE_HOME="$migration_home/.local/state" \
    HYPRCTL_LOG="$tmpdir/migration-hyprctl.log" PATH="$stub_dir:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

migration_log="$tmpdir/migration-hyprctl.log"
: >"$migration_log"
run_migration || fail "the migration exits cleanly with a layout to remove"

if [[ -f $migration_layouts/-1337.lua ]]; then
  fail "the migration removes a saved layout for a named workspace"
fi
[[ -f $migration_layouts/3.lua ]] ||
  fail "the migration keeps saved layouts for numbered workspaces"

# The bad rule is already applied in the running session, and a user who has
# turned autoreload off would keep it until their next login.
grep -q "^reload" "$migration_log" ||
  fail "the migration asks Hyprland to reload what it removed" "$(cat "$migration_log")"

# The ordinary case is a machine with nothing to remove, where the glob matches
# no file at all.
: >"$migration_log"
run_migration || fail "the migration exits cleanly with nothing to remove"
[[ -f $migration_layouts/3.lua ]] ||
  fail "the migration with nothing to remove keeps what is there"
if grep -q "^reload" "$migration_log"; then
  fail "the migration reloads Hyprland having removed nothing" "$(cat "$migration_log")"
fi
pass "the migration removes saved layouts for named workspaces"

if toggle HYPRCTL_BROKEN=1 2>/dev/null; then
  fail "workspace layout toggle exits nonzero without a workspace id"
fi
if [[ -f $home_dir/.local/state/omarchy/workspace-layouts/null.lua ]]; then
  fail "workspace layout toggle does not persist a mode without a workspace id"
fi
pass "workspace layout toggle ignores broken hyprctl output"

# A state home somewhere else has to work end to end: the shell writes there and
# Hyprland loads from there. Saving to one place and restoring from another is a
# mode that silently never comes back.
state_home="$tmpdir/state"
toggle XDG_STATE_HOME="$state_home"
[[ -f $state_home/omarchy/workspace-layouts/3.lua ]] ||
  fail "workspace layout toggle honours XDG_STATE_HOME"

# A decoy of the same name under the home directory, saying something else. The
# loader lists the custom state home but loads by module name, so without the
# search path it finds this one and the mode restored is the wrong one.
printf 'hl.workspace_rule({ workspace = "3", layout = "dwindle" })\n' >"$layout_file"

xdg_probe="$tmpdir/xdg-probe.lua"
cat >"$xdg_probe" <<'LUA'
local applied = {}

hl = {
  workspace_rule = function(rule)
    table.insert(applied, rule)
  end,
  get_workspace_windows = function()
    return {}
  end,
  get_windows = function()
    return {}
  end,
  dispatch = function() end,
  dsp = { window = { float = function(spec) return spec end, tag = function(spec) return spec end } },
  on = function() end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.helpers")
require("default.hypr.workspace-layouts")

assert(#applied == 1, "a mode saved under XDG_STATE_HOME was not restored")
assert(applied[1].workspace == "3", "the restored mode named the wrong workspace")
assert(applied[1].layout == "scrolling", "the restored mode was not the one saved")
LUA

if ! HOME="$home_dir" XDG_STATE_HOME="$state_home" OMARCHY_PATH="$ROOT" lua "$xdg_probe"; then
  fail "a mode saved under XDG_STATE_HOME is restored from there"
fi
pass "workspace layout toggle saves and restores through XDG_STATE_HOME"

printf 'o.workspace_mode({ workspace = "3", mode = "floating" })\n' >"$layout_file"

lua_script="$tmpdir/workspace-modes.lua"

cat >"$lua_script" <<'LUA'
local workspace_rules = {}
local subscriptions = {}
local queried = {}
local all = {}

local function window(address, options)
  options = options or {}

  local created = {
    address = address,
    floating = options.floating or false,
    pinned = options.pinned or false,
    group = options.group,
    tags = {},
    workspace = { id = options.workspace or 3 },
  }

  table.insert(all, created)

  return created
end

local function has_tag(target, tag)
  for _, held in ipairs(target.tags) do
    if held == tag then
      return true
    end
  end

  return false
end

-- Two plain windows, one already floating on its own account, and a group whose
-- members float together the way Hyprland floats a group target.
local tiled = window("0xA")
local already = window("0xB", { floating = true })
local grouped = window("0xC", { group = "g" })
local partner = window("0xD", { group = "g" })
local pinned = window("0x12")

hl = {
  workspace_rule = function(rule)
    table.insert(workspace_rules, rule)
  end,
  get_workspace_windows = function(selector)
    table.insert(queried, tostring(selector))

    local found = {}
    for _, candidate in ipairs(all) do
      if tostring(candidate.workspace.id) == tostring(selector) then
        table.insert(found, candidate)
      end
    end

    return found
  end,
  get_windows = function(filter)
    local found = {}
    for _, candidate in ipairs(all) do
      if filter and filter.tag and has_tag(candidate, filter.tag) then
        table.insert(found, candidate)
      end
    end

    return found
  end,
  dispatch = function(action)
    local target = action.window

    if action.tag then
      local name = action.tag:sub(2)

      if action.tag:sub(1, 1) == "+" then
        if not has_tag(target, name) then
          table.insert(target.tags, name)
        end
      else
        for index, held in ipairs(target.tags) do
          if held == name then
            table.remove(target.tags, index)
            break
          end
        end
      end
    else
      -- Floating a grouped window takes the rest of its group with it.
      for _, candidate in ipairs(all) do
        if candidate == target or (target.group and candidate.group == target.group) then
          candidate.floating = action.action == "on"
        end
      end
    end
  end,
  dsp = {
    window = {
      float = function(spec) return spec end,
      tag = function(spec) return spec end,
    },
  },
  on = function(event, callback)
    subscriptions[event] = subscriptions[event] or {}
    table.insert(subscriptions[event], callback)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.helpers")
require("default.hypr.workspace-layouts")

local CLAIMED = "omarchy-mode-floated"

-- Floating is not a layout, so the saved file must not have asked Hyprland for
-- one by that name: Hyprland takes an unknown layout in silence and falls back
-- to dwindle.
assert(#workspace_rules == 0, "floating asked Hyprland for a layout")

-- The windows of the workspace the file named, not of some other one.
assert(#queried == 1 and queried[1] == "3", "the wrong workspace was queried: " .. table.concat(queried, ","))

assert(tiled.floating == true, "the tiled window was not floated")
assert(has_tag(tiled, CLAIMED), "the window the mode floated was not claimed")
assert(already.floating == true, "the already floating window changed")
assert(not has_tag(already, CLAIMED), "a window floating on its own account was claimed")

-- Every member of a group is claimed. Floating one floats them all, so claiming
-- as it goes would find the rest already floating and leave them unclaimed.
assert(grouped.floating == true and partner.floating == true, "the group was not floated")
assert(has_tag(grouped, CLAIMED) and has_tag(partner, CLAIMED), "a group member went unclaimed")

-- One handler each: subscribing on every call would float a window as many
-- times as the mode has ever been set.
assert(#subscriptions["window.open"] == 1, "window.open subscribed more than once")
assert(#subscriptions["window.move_to_workspace"] == 1, "moves subscribed more than once")

local opened = subscriptions["window.open"][1]
local moved = subscriptions["window.move_to_workspace"][1]

-- A window opening on a floating workspace floats; one that arrives floating
-- already is left alone, so the mode never claims it.
local fresh = window("0xE")
opened(fresh)
assert(fresh.floating == true, "a window opened on a floating workspace stayed tiled")
assert(has_tag(fresh, CLAIMED), "a window opened into the mode was not claimed")

local own_rule = window("0xF", { floating = true })
opened(own_rule)
assert(not has_tag(own_rule, CLAIMED), "a window with its own float rule was claimed")

-- A window carried onto a floating workspace never had that workspace's mode
-- applied to it.
local carried = window("0x10", { workspace = 4 })
moved(carried, { id = 3 })
assert(carried.floating == true, "a window carried onto a floating workspace stayed tiled")

-- Carried on to a tiled workspace, the mode gives back what it took.
carried.workspace.id = 5
moved(carried, { id = 5 })
assert(carried.floating == false, "a window the mode floated stayed floating on a tiled workspace")
assert(not has_tag(carried, CLAIMED), "a window the mode gave back is still claimed")

-- A window floating on its own account keeps floating wherever it goes.
moved(own_rule, { id = 5 })
assert(own_rule.floating == true, "a window floating on its own account was tiled by a move")

-- Carried between two floating workspaces it stays claimed, so the workspace it
-- ends on can still give it back.
o.workspace_mode({ workspace = "6", mode = "floating" })
tiled.workspace.id = 6
moved(tiled, { id = 6 })
assert(tiled.floating == true, "a window moved between floating workspaces was tiled")
assert(has_tag(tiled, CLAIMED), "a window moved between floating workspaces lost its claim")

o.workspace_mode({ workspace = "6", mode = "dwindle" })
assert(tiled.floating == false, "the workspace a claimed window moved to could not give it back")

-- A pinned window was put above everything on purpose, and tiling it would unpin
-- it too, so the mode leaves it where the user put it.
assert(has_tag(pinned, CLAIMED), "the window to be pinned was never claimed")
pinned.pinned = true

-- Ending the mode tiles what the mode claimed, and only that.
o.workspace_mode({ workspace = "3", mode = "dwindle" })
assert(#workspace_rules == 2, "leaving floating did not set a layout")
assert(workspace_rules[2].layout == "dwindle")
assert(workspace_rules[2].workspace == "3", "the layout was applied to the wrong workspace")
assert(grouped.floating == false, "the window the mode floated was left floating")
assert(already.floating == true, "a window floating on its own account was tiled by the mode ending")
assert(partner.floating == false, "a group member the mode floated was left floating")
assert(pinned.floating == true, "a pinned window was tiled by the mode ending")
assert(has_tag(pinned, CLAIMED), "a pinned window lost the claim that returns it once unpinned")

-- Still one handler each after a second mode: the count above was taken before
-- this call, so only a check on this side catches subscribing every time.
assert(#subscriptions["window.open"] == 1, "window.open subscribed again on the next mode")
assert(#subscriptions["window.move_to_workspace"] == 1, "moves subscribed again on the next mode")

-- The workspace is tiled now, so nothing opening on it should float.
local after = window("0x11")
opened(after)
assert(after.floating == false, "a window opened after the mode ended was floated")

-- Scrolling is a layout like dwindle, and has to reach Hyprland as one.
o.workspace_mode({ workspace = "3", mode = "scrolling" })
assert(workspace_rules[#workspace_rules].layout == "scrolling", "scrolling was not applied as a layout")
assert(workspace_rules[#workspace_rules].workspace == "3")
LUA

# Lua 5.5 exits 0 when a script that failed came in on stdin, so a heredoc piped
# straight into lua reports every assertion above as passing. Run it as a file.
# XDG_STATE_HOME is named here for the same reason the toggle helper names it:
# the loader reads the saved modes from paths.state_home, so a machine that
# exports it would load its own saved layouts instead of the fixture below.
if ! HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" OMARCHY_PATH="$ROOT" \
  lua "$lua_script"; then
  fail "a saved floating mode floats the workspace without inventing a layout"
fi
pass "a saved floating mode floats the workspace without inventing a layout"
