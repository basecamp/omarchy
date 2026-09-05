#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local Module = require("default.hypr.window-vault")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_true(value, message)
  if not value then
    error(message, 2)
  end
end

local function action_seen(actions, kind, predicate)
  for _, action in ipairs(actions) do
    if action.kind == kind and (not predicate or predicate(action)) then
      return true
    end
  end

  return false
end

local function new_context()
  local actions = {}
  local notifications = {}
  local listeners = {}
  local active

  local workspaces = {
    ["1"] = { name = "1", config_name = "1", special = false },
    ["2"] = { name = "2", config_name = "2", special = false },
    ["name:writing"] = { name = "writing", config_name = "name:writing", special = false },
    [Module.VAULT_WORKSPACE] = {
      name = Module.VAULT_WORKSPACE,
      config_name = Module.VAULT_WORKSPACE,
      special = true,
    },
  }

  local function record(kind, fields)
    fields = fields or {}
    fields.kind = kind
    table.insert(actions, fields)
  end

  local api = {
    active_window = function()
      return active
    end,
    move_to_workspace = function(window, workspace, follow)
      record("move-workspace", { window = window, workspace = workspace, follow = follow })
      window.workspace = workspaces[workspace] or {
        name = workspace,
        config_name = workspace,
        special = workspace:sub(1, 8) == "special:",
      }
    end,
    move_exact = function(window, point)
      record("move-exact", { window = window, x = point.x, y = point.y })
    end,
    resize_exact = function(window, size)
      record("resize-exact", { window = window, x = size.x, y = size.y })
    end,
    set_floating = function(window, enabled)
      record("floating", { window = window, enabled = enabled })
      window.floating = enabled
    end,
    set_pinned = function(window, enabled)
      record("pinned", { window = window, enabled = enabled })
      window.pinned = enabled
    end,
    set_fullscreen_state = function(window, internal, client)
      record("fullscreen", { window = window, internal = internal, client = client })
      window.fullscreen = internal
      window.fullscreen_client = client
    end,
    focus = function(window)
      record("focus", { window = window })
      active = window
    end,
    close = function(window)
      record("close", { window = window })
    end,
    toggle = function()
      record("toggle")
    end,
    remove_from_group = function(group, window)
      record("group-remove", { group = group, window = window })
      for index, member in ipairs(group.members) do
        if member == window then
          table.remove(group.members, index)
          break
        end
      end
    end,
    add_to_group = function(group, window, index)
      record("group-add", { group = group, window = window, index = index })
      table.insert(group.members, index, window)
    end,
    group_available = function(group)
      return group and group.available ~= false
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
    defer = function(callback)
      callback()
    end,
    on = function(event, callback)
      listeners[event] = callback
    end,
  }

  local vault = Module.new(api, {})
  vault:install_listeners()

  return {
    actions = actions,
    notifications = notifications,
    listeners = listeners,
    vault = vault,
    workspaces = workspaces,
    set_active = function(window)
      active = window
    end,
  }
end

local function window(address, workspace, fields)
  local result = fields or {}
  result.address = address
  result.mapped = result.mapped ~= false
  result.workspace = workspace
  result.title = result.title or address
  result.class = result.class or "test-app"
  result.tags = result.tags or {}
  result.at = result.at or { x = 40, y = 50 }
  result.size = result.size or { x = 800, y = 600 }
  result.floating = result.floating == true
  result.pinned = result.pinned == true
  result.fullscreen = result.fullscreen or 0
  result.fullscreen_client = result.fullscreen_client or 0
  return result
end

assert_equal(Module.workspace_selector({ name = "3", special = false }), "3", "numeric workspace selector is preserved")
assert_equal(Module.workspace_selector({ name = "writing", special = false }), "name:writing", "named workspace selector is qualified")
assert_equal(Module.workspace_selector({ name = "scratchpad", special = true }), "special:scratchpad", "special workspace selector is qualified")

do
  local context = new_context()
  local other = window("0xother", context.workspaces["2"])
  local target = window("0xtarget", context.workspaces["2"], {
    title = "Unsaved draft",
    floating = true,
    pinned = true,
    fullscreen = 2,
    fullscreen_client = 1,
    at = { x = 120, y = 140 },
    size = { x = 900, y = 700 },
  })
  local group = { members = { other, target }, available = true }
  target.group = group
  context.set_active(target)

  assert_true(context.vault:stash_active(), "active window is vaulted")
  assert_equal(#context.vault.state.entries, 1, "vault records one entry")
  assert_equal(target.workspace.config_name, Module.VAULT_WORKSPACE, "window moves to the vault workspace")
  assert_true(action_seen(context.actions, "fullscreen", function(action)
    return action.internal == 0 and action.client == 0
  end), "vault clears fullscreen state")
  assert_true(action_seen(context.actions, "pinned", function(action)
    return action.enabled == false
  end), "vault clears pinned state")
  assert_true(action_seen(context.actions, "group-remove"), "vault removes only the selected group member")
  assert_true(context.notifications[#context.notifications]:find("still running", 1, true), "vault explains that the app remains running")

  assert_true(context.vault:restore_latest(), "latest window restores")
  assert_equal(#context.vault.state.entries, 0, "restore removes the history entry")
  assert_equal(target.workspace.config_name, "2", "restore returns to the original workspace")
  assert_true(action_seen(context.actions, "move-exact", function(action)
    return action.x == 120 and action.y == 140
  end), "floating position restores")
  assert_true(action_seen(context.actions, "resize-exact", function(action)
    return action.x == 900 and action.y == 700
  end), "floating size restores")
  assert_true(action_seen(context.actions, "group-add", function(action)
    return action.index == 2
  end), "group position restores when the group still exists")
  assert_true(action_seen(context.actions, "pinned", function(action)
    return action.enabled == true
  end), "pinned state restores")
  assert_true(action_seen(context.actions, "fullscreen", function(action)
    return action.internal == 2 and action.client == 1
  end), "client and compositor fullscreen states restore")
  assert_true(action_seen(context.actions, "focus", function(action)
    return action.window == target
  end), "restored window receives focus")
end

do
  local context = new_context()
  local first = window("0xfirst", context.workspaces["1"])
  local second = window("0xsecond", context.workspaces["2"])

  context.set_active(first)
  context.vault:stash_active()
  context.set_active(second)
  context.vault:stash_active()

  context.vault:restore_latest()
  assert_equal(second.workspace.config_name, "2", "restore is last-in first-out")
  assert_equal(first.workspace.config_name, Module.VAULT_WORKSPACE, "older vaulted window stays hidden")

  context.vault:close_latest()
  assert_true(action_seen(context.actions, "close", function(action)
    return action.window == first and first.workspace.config_name == "1"
  end), "closing a vaulted window restores it before requesting close")
end

do
  local context = new_context()
  local tagged = window("0xtagged", context.workspaces["1"], {
    tags = { Module.NO_VAULT_TAG .. "*" },
  })
  context.set_active(tagged)

  context.vault:stash_active()
  assert_equal(#context.vault.state.entries, 0, "no-vault tag bypasses history")
  assert_true(action_seen(context.actions, "close", function(action)
    return action.window == tagged
  end), "no-vault tag uses the normal graceful close")
end

do
  local context = new_context()
  local target = window("0xstale", context.workspaces["1"])
  context.set_active(target)
  context.vault:stash_active()

  context.listeners["window.destroy"](target)
  assert_equal(#context.vault.state.entries, 0, "destroyed windows are removed from history")

  target.workspace = context.workspaces["1"]
  context.set_active(target)
  context.vault:stash_active()
  assert_equal(#context.vault.state.entries, 1, "window is vaulted again before the manual-move check")
  context.listeners["window.move_to_workspace"](target, context.workspaces["name:writing"])
  assert_equal(#context.vault.state.entries, 0, "manually restored windows are removed from history")
end

do
  local context = new_context()
  assert_true(not context.vault:toggle(), "empty vault does not open")
  assert_equal(context.notifications[#context.notifications], "Window Vault is empty", "empty vault reports its state")

  local target = window("0xtoggle", context.workspaces["1"])
  context.set_active(target)
  context.vault:stash_active()
  assert_true(context.vault:toggle(), "non-empty vault opens")
  assert_true(action_seen(context.actions, "toggle"), "vault toggle uses the special workspace")
end
LUA

pass "window vault preserves live window state and cleans stale history"
