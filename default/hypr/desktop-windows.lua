-- Desktop Mode windowing: overlapping floats, compositor title bars, work-area snap.
-- Loaded instead of default.hypr.windows when Ultimate mode is desktop.

o.window(".*", { float = true })
o.window(".*", { tag = "+default-opacity" })
-- Open as an overlapping float, not a 50/50 tile leftover from a snap probe.
o.window(".*", { size = { 880, 560 } })
-- xdg modal dialogs keep the size they asked for instead of the 880×560 app default.
o.window({ modal = true }, { float = true, center = true, size = { "window_w", "window_h" } })

-- Fix some dragging issues with XWayland.
o.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

require("default.hypr.apps")

o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })

hl.config({
  general = {
    resize_on_border = true,
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
    col = {
      active_border = "rgba(6a6a6aff)",
      inactive_border = "rgba(3a3a3aff)",
    },
  },
  group = {
    col = {
      border_active = "rgba(6a6a6aff)",
      border_inactive = "rgba(3a3a3aff)",
    },
  },
  decoration = {
    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
    },
  },
  cursor = {
    hide_on_key_press = false,
  },
  plugin = {
    hyprbars = {
      enabled = true,
      bar_height = 32,
      bar_part_of_window = true,
      bar_precedence_over_border = true,
      bar_padding = 8,
      bar_button_padding = 6,
      bar_title_enabled = true,
      bar_text_size = 13,
      bar_text_font = "sans-serif",
      bar_text_align = "left",
      bar_buttons_alignment = "right",
      icon_on_hover = false,
      bar_color = "rgba(1a1a1acc)",
      ["col.text"] = "rgb(eeeeee)",
      on_double_click = "omarchy-shell window toggleMaximize active",
    },
  },
})

pcall(function()
  hl.permission("/usr/lib/hyprland-plugins/hyprbars.so", "plugin", "allow")
  hl.permission("/usr/lib/hyprland-plugins/omarchy-minimize.so", "plugin", "allow")
  hl.permission("/usr/local/lib/hyprland-plugins/hyprbars.so", "plugin", "allow")
  hl.permission("/usr/local/lib/hyprland-plugins/omarchy-minimize.so", "plugin", "allow")
  hl.permission(".*/default/hypr/plugins/hyprbars/hyprbars.so", "plugin", "allow")
  hl.permission(".*/default/hypr/plugins/omarchy-minimize/omarchy-minimize.so", "plugin", "allow")
end)

local function plugin_table()
  local plugin = hl.plugin
  if type(plugin) ~= "table" then
    return nil
  end
  return plugin
end

local function hyprbars_ready()
  local plugin = plugin_table()
  return plugin ~= nil and plugin.hyprbars ~= nil
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function load_so(path)
  if not file_exists(path) then
    return false
  end
  hl.exec_cmd("hyprctl plugin load " .. path)
  return true
end

local function first_existing(candidates)
  local i
  for i = 1, #candidates do
    if file_exists(candidates[i]) then
      return candidates[i]
    end
  end
  return nil
end

local function load_hyprbars()
  if hyprbars_ready() then
    return true
  end
  local omarchy = os.getenv("OMARCHY_PATH") or ""
  local candidates = {
    "/usr/lib/hyprland-plugins/hyprbars.so",
    "/usr/local/lib/hyprland-plugins/hyprbars.so",
  }
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/hyprbars/hyprbars.so"
  end
  local path = first_existing(candidates)
  if not path then
    return false
  end
  return load_so(path)
end

local function minimize_ready()
  local plugin = plugin_table()
  return plugin ~= nil and plugin.omarchy_minimize ~= nil
end

local function load_omarchy_minimize()
  if minimize_ready() then
    return true
  end
  local omarchy = os.getenv("OMARCHY_PATH") or ""
  local candidates = {
    "/usr/lib/hyprland-plugins/omarchy-minimize.so",
    "/usr/local/lib/hyprland-plugins/omarchy-minimize.so",
  }
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/omarchy-minimize/omarchy-minimize.so"
  end
  local path = first_existing(candidates)
  if not path then
    return false
  end
  return load_so(path)
end

local function add_hyprbars_buttons()
  if _G.omarchy_hyprbars_buttons then
    return
  end
  local plugin = plugin_table()
  if not (plugin and plugin.hyprbars and plugin.hyprbars.add_button) then
    return
  end
  -- hyprbars draws buttons right-to-left: close, maximize, minimize.
  plugin.hyprbars.add_button({
    bg_color = "rgb(c42b1c)",
    fg_color = "rgb(ffffff)",
    size = 14,
    icon = "×",
    action = "omarchy-shell window closeActive",
  })
  plugin.hyprbars.add_button({
    bg_color = "rgb(3d3d3d)",
    fg_color = "rgb(ffffff)",
    size = 14,
    icon = "□",
    action = "omarchy-shell window toggleMaximize active",
  })
  plugin.hyprbars.add_button({
    bg_color = "rgb(3d3d3d)",
    fg_color = "rgb(ffffff)",
    size = 14,
    icon = "▦",
    action = "omarchy-shell window snapChooser active",
  })
  plugin.hyprbars.add_button({
    bg_color = "rgb(3d3d3d)",
    fg_color = "rgb(ffffff)",
    size = 14,
    icon = "–",
    action = "omarchy-shell window minimize active",
  })
  _G.omarchy_hyprbars_buttons = true
end

load_hyprbars()
add_hyprbars_buttons()
load_omarchy_minimize()

hl.on("hyprland.start", function()
  load_hyprbars()
  add_hyprbars_buttons()
  load_omarchy_minimize()
end)
