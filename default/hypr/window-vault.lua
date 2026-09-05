-- Keep accidentally closed windows alive until the user restores or closes them.

local WindowVault = {}
WindowVault.__index = WindowVault

local VAULT_WORKSPACE = "special:omarchy-window-vault"
local NO_VAULT_TAG = "omarchy-no-window-vault"

local function copy_point(point)
  if not point then
    return nil
  end

  return { x = point.x, y = point.y }
end

local function workspace_selector(workspace)
  if not workspace then
    return nil
  end

  if workspace.config_name and workspace.config_name ~= "" then
    return workspace.config_name
  end

  local name = workspace.name
  if not name or name == "" then
    return nil
  end

  if workspace.special then
    if name:sub(1, 8) == "special:" then
      return name
    end

    return "special:" .. name
  end

  if tonumber(name) then
    return name
  end

  if name:sub(1, 5) == "name:" then
    return name
  end

  return "name:" .. name
end

local function window_address(window)
  return window and window.address or nil
end

local function window_is_alive(window)
  return window ~= nil and window.mapped ~= false and window_address(window) ~= nil
end

local function window_has_tag(window, wanted)
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == wanted then
      return true
    end
  end

  return false
end

local function window_label(window)
  local title = tostring(window.title or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if title ~= "" then
    return title
  end

  local class = tostring(window.class or ""):match("^%s*(.-)%s*$")
  if class ~= "" then
    return class
  end

  return "Window"
end

local function group_index(group, window)
  if not group or not group.members then
    return nil
  end

  for index, member in ipairs(group.members) do
    if member == window then
      return index
    end
  end

  return nil
end

local function normalized_state(state)
  local next_state = state or {}
  next_state.entries = next_state.entries or {}
  next_state.timers = next_state.timers or {}
  return next_state
end

local function default_api(state)
  local function dispatch(dispatcher)
    hl.dispatch(dispatcher)
  end

  local function defer(callback, timeout)
    local timer
    timer = hl.timer(function()
      state.timers[timer] = nil
      callback()
    end, { timeout = timeout, type = "oneshot" })

    if timer then
      state.timers[timer] = true
    end
  end

  return {
    active_window = function()
      return hl.get_active_window()
    end,
    move_to_workspace = function(window, workspace, follow)
      dispatch(hl.dsp.window.move({ window = window, workspace = workspace, follow = follow }))
    end,
    move_exact = function(window, point)
      dispatch(hl.dsp.window.move({ window = window, x = point.x, y = point.y }))
    end,
    resize_exact = function(window, size)
      dispatch(hl.dsp.window.resize({ window = window, x = size.x, y = size.y }))
    end,
    set_floating = function(window, enabled)
      dispatch(hl.dsp.window.float({ window = window, action = enabled and "set" or "unset" }))
    end,
    set_pinned = function(window, enabled)
      dispatch(hl.dsp.window.pin({ window = window, action = enabled and "set" or "unset" }))
    end,
    set_fullscreen_state = function(window, internal, client)
      dispatch(hl.dsp.window.fullscreen_state({
        window = window,
        internal = internal,
        client = client,
        action = "set",
      }))
    end,
    focus = function(window)
      dispatch(hl.dsp.focus({ window = window }))
    end,
    close = function(window)
      dispatch(hl.dsp.window.close({ window = window }))
    end,
    toggle = function()
      dispatch(hl.dsp.workspace.toggle_special("omarchy-window-vault"))
    end,
    remove_from_group = function(group, window)
      group:remove(window)
    end,
    add_to_group = function(group, window, index)
      group:add(window, index)
    end,
    group_available = function(group)
      return group ~= nil and group.size ~= nil and group.add ~= nil
    end,
    notify = function(message)
      hl.exec_cmd(o.notify(message))
    end,
    defer = defer,
    on = function(event, callback)
      return hl.on(event, callback)
    end,
  }
end

function WindowVault.new(api, state)
  return setmetatable({
    api = api,
    state = normalized_state(state),
  }, WindowVault)
end

function WindowVault:index_of(window)
  local address = window_address(window)
  if not address then
    return nil
  end

  for index, entry in ipairs(self.state.entries) do
    if entry.address == address then
      return index
    end
  end

  return nil
end

function WindowVault:remove_at(index)
  if index then
    return table.remove(self.state.entries, index)
  end

  return nil
end

function WindowVault:prune()
  for index = #self.state.entries, 1, -1 do
    local window = self.state.entries[index].window
    if not window_is_alive(window) or workspace_selector(window.workspace) ~= VAULT_WORKSPACE then
      self:remove_at(index)
    end
  end
end

function WindowVault:capture(window)
  local workspace = workspace_selector(window.workspace)
  if not workspace then
    return nil
  end

  return {
    window = window,
    address = window_address(window),
    label = window_label(window),
    workspace = workspace,
    position = copy_point(window.at),
    size = copy_point(window.size),
    floating = window.floating == true,
    pinned = window.pinned == true,
    fullscreen = tonumber(window.fullscreen) or 0,
    fullscreen_client = tonumber(window.fullscreen_client) or 0,
    group = window.group,
    group_index = group_index(window.group, window),
  }
end

function WindowVault:stash_active()
  self:prune()

  local window = self.api.active_window()
  if not window_is_alive(window) then
    return false
  end

  if workspace_selector(window.workspace) == VAULT_WORKSPACE then
    self.api.notify("This window is already in the Window Vault")
    return false
  end

  if window_has_tag(window, NO_VAULT_TAG) then
    self.api.close(window)
    return true
  end

  if self:index_of(window) then
    return false
  end

  local entry = self:capture(window)
  if not entry then
    self.api.close(window)
    return true
  end

  if entry.fullscreen ~= 0 or entry.fullscreen_client ~= 0 then
    self.api.set_fullscreen_state(window, 0, 0)
  end

  if entry.pinned then
    self.api.set_pinned(window, false)
  end

  if entry.group and entry.group_index then
    self.api.remove_from_group(entry.group, window)
  end

  self.api.move_to_workspace(window, VAULT_WORKSPACE, false)
  table.insert(self.state.entries, entry)
  self.api.notify(entry.label .. " is still running in the Window Vault — Super+Shift+T restores it")
  return true
end

function WindowVault:pop_latest()
  self:prune()

  while #self.state.entries > 0 do
    local entry = self:remove_at(#self.state.entries)
    if window_is_alive(entry.window) then
      return entry
    end
  end

  return nil
end

function WindowVault:restore_entry(entry, after_restore)
  local window = entry.window
  self.api.move_to_workspace(window, entry.workspace, true)

  self.api.defer(function()
    if not window_is_alive(window) then
      return
    end

    self.api.set_floating(window, entry.floating)

    if entry.floating then
      if entry.position then
        self.api.move_exact(window, entry.position)
      end

      if entry.size then
        self.api.resize_exact(window, entry.size)
      end
    end

    if entry.group and entry.group_index and self.api.group_available(entry.group) then
      self.api.add_to_group(entry.group, window, entry.group_index)
    end

    if entry.pinned then
      self.api.set_pinned(window, true)
    end

    if entry.fullscreen ~= 0 or entry.fullscreen_client ~= 0 then
      self.api.set_fullscreen_state(window, entry.fullscreen, entry.fullscreen_client)
    end

    self.api.focus(window)

    if after_restore then
      after_restore(window)
    end
  end, 1)
end

function WindowVault:restore_latest()
  local entry = self:pop_latest()
  if not entry then
    self.api.notify("Window Vault is empty")
    return false
  end

  self:restore_entry(entry)
  self.api.notify("Restored " .. entry.label)
  return true
end

function WindowVault:close_latest()
  local entry = self:pop_latest()
  if not entry then
    self.api.notify("Window Vault is empty")
    return false
  end

  self:restore_entry(entry, function(window)
    self.api.close(window)
  end)
  self.api.notify("Closing " .. entry.label)
  return true
end

function WindowVault:toggle()
  self:prune()
  if #self.state.entries == 0 then
    self.api.notify("Window Vault is empty")
    return false
  end

  self.api.toggle()
  return true
end

function WindowVault:install_listeners()
  self.api.on("window.destroy", function(window)
    self:remove_at(self:index_of(window))
  end)

  self.api.on("window.move_to_workspace", function(window, workspace)
    local index = self:index_of(window)
    if index and workspace_selector(workspace) ~= VAULT_WORKSPACE then
      self:remove_at(index)
    end
  end)
end

local Module = {
  VAULT_WORKSPACE = VAULT_WORKSPACE,
  NO_VAULT_TAG = NO_VAULT_TAG,
  new = WindowVault.new,
  workspace_selector = workspace_selector,
}

function Module.for_hyprland()
  local state = normalized_state(rawget(_G, "omarchy_window_vault_state"))
  rawset(_G, "omarchy_window_vault_state", state)

  local vault = WindowVault.new(default_api(state), state)
  vault:install_listeners()
  return vault
end

return Module
