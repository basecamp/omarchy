-- Shared helpers for Hyprland Lua configuration.

o = o or {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function o.bind(keys, description, dispatcher, options)
  local opts = options or {}

  if description then
    opts.description = description
  end

  if type(dispatcher) == "string" then
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

function o.bind_launch(keys, description, command, options)
  o.bind(keys, description, o.launch(command), options)
end

function o.launch_webapp(url)
  return "omarchy-launch-webapp " .. shell_quote(url)
end

function o.launch_webapp_sole(name, url)
  return "omarchy-launch-or-focus-webapp " .. shell_quote(name) .. " " .. shell_quote(url)
end

function o.bind_webapp(keys, description, url, options)
  o.bind(keys, description, o.launch_webapp(url), options)
end

function o.bind_webapp_sole(keys, description, url, options)
  o.bind(keys, description, o.launch_webapp_sole(description, url), options)
end

function o.bind_menu(keys, description, menu, options)
  o.bind(keys, description, menu and ("omarchy-menu " .. menu) or "omarchy-menu", options)
end

function o.bind_toggle(keys, description, toggle, options)
  o.bind(keys, description, "omarchy-toggle-" .. toggle, options)
end

function o.notify(message)
  return "notify-send -u low " .. shell_quote(message)
end
