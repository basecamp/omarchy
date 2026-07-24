-- Shared helpers for Hyprland Lua configuration.

o = o or {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

o.shell_quote = shell_quote

local function file_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end

  return false
end

function o.shell_succeeds(command)
  local ok, _, code = os.execute(command .. " >/dev/null 2>&1")
  return ok == true or ok == 0 or code == 0
end

function o.cmd_present(command)
  if command:find("/", 1, true) then
    return file_exists(command)
  end

  local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
  for directory in (path .. ":"):gmatch("([^:]*):") do
    if file_exists((directory ~= "" and directory or ".") .. "/" .. command) then
      return true
    end
  end

  return false
end

function o.cmd_missing(command)
  return not o.cmd_present(command)
end

local function command_from(value, description)
  if type(value) ~= "table" then
    return value
  end

  if value.omarchy then
    return "omarchy-launch-" .. value.omarchy
  elseif value.focus and value.launch then
    return o.launch_sole(value.focus, value.launch)
  elseif value.launch then
    return o.launch(value.launch)
  elseif value.webapp then
    if value.focus then
      return o.launch_webapp_sole(description, value.webapp)
    else
      return o.launch_webapp(value.webapp)
    end
  elseif value.tui then
    if value.focus then
      return "omarchy-launch-or-focus-tui " .. shell_quote(value.tui)
    else
      return "omarchy-launch-tui " .. shell_quote(value.tui)
    end
  end

  return value
end

function o.preinstalled_bindings_enabled()
  if _G.omarchy_preinstalled_bindings ~= nil then
    return _G.omarchy_preinstalled_bindings == true
  end

  return not file_exists((os.getenv("HOME") or "") .. "/.local/state/omarchy/preinstalls-removed")
end

local function bind_dedup_key(keys, options)
  if not options then
    return keys
  end

  -- Internal dedup key: same keys with a different event type
  if options.release then
    return keys .. "|r"
  elseif options.long_press then
    return keys .. "|l"
  end

  return keys
end

local registered = {}

function o.bind(keys, description, dispatcher, options)
  local opts = options or {}

  if description then
    opts.description = description
  end

  dispatcher = command_from(dispatcher, description)
  local disp_is_launch = type(dispatcher) == "string"
  local dedup = bind_dedup_key(keys, options)

  if registered[dedup] ~= nil and (disp_is_launch or registered[dedup]) then
    hl.unbind(keys)
  end

  registered[dedup] = disp_is_launch

  if disp_is_launch then
    dispatcher = hl.dsp.exec_cmd(dispatcher)
  end

  hl.bind(keys, dispatcher, opts)
end

function o.launch(command)
  return "uwsm-app -- " .. command
end

function o.exec_on_start(command)
  hl.on("hyprland.start", function()
    hl.exec_cmd(command)
  end)
end

function o.launch_on_start(command)
  o.exec_on_start(o.launch(command))
end

function o.launch_webapp(url)
  return "omarchy-launch-webapp " .. shell_quote(url)
end

function o.launch_webapp_sole(name, url)
  return "omarchy-launch-or-focus-webapp " .. shell_quote(name) .. " " .. shell_quote(url)
end

function o.launch_sole(match, command)
  return "omarchy-launch-or-focus " .. shell_quote(match) .. " " .. shell_quote(o.launch(command))
end

function o.bind_toggle(keys, description, toggle, options)
  o.bind(keys, description, "omarchy-toggle-" .. toggle, options)
end

function o.notify(message)
  return "notify-send -u low " .. shell_quote(message)
end

function o.window(match, rules)
  rules.match = rules.match or {}

  if type(match) == "string" then
    rules.match.class = match
  else
    for key, value in pairs(match) do
      rules.match[key] = value
    end
  end

  hl.window_rule(rules)
end
