-- Desktop Mode windowing: overlapping floats, compositor title bars, work-area snap.
-- Loaded instead of default.hypr.windows when Ultimate mode is desktop.

o.window(".*", { float = true })
o.window(".*", { tag = "+default-opacity" })
-- Open as an overlapping float, not a 50/50 tile leftover from a snap probe.
o.window(".*", { size = { 880, 560 } })

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
    border_size = 2,
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
  hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
  hl.permission("/var/cache/hyprpm/.*/hyprland-plugins/hyprbars.so", "plugin", "allow")
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

local function load_hyprbars()
  if hyprbars_ready() then
    return true
  end
  local user = os.getenv("USER") or os.getenv("LOGNAME") or ""
  local candidates = {
    "/usr/lib/hyprland-plugins/hyprbars.so",
    "/usr/local/lib/hyprland-plugins/hyprbars.so",
  }
  if user ~= "" then
    candidates[#candidates + 1] = "/var/cache/hyprpm/" .. user .. "/hyprland-plugins/hyprbars.so"
  end
  local i
  for i = 1, #candidates do
    local path = candidates[i]
    local file = io.open(path, "r")
    if file then
      file:close()
      hl.exec_cmd("hyprctl plugin load " .. path)
      return true
    end
  end
  return false
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
    icon = "–",
    action = "omarchy-shell window minimize active",
  })
  _G.omarchy_hyprbars_buttons = true
end

load_hyprbars()
add_hyprbars_buttons()

hl.on("hyprland.start", function()
  if o.cmd_present("hyprpm") then
    hl.exec_cmd("hyprpm reload -n")
  end
  load_hyprbars()
  add_hyprbars_buttons()
end)
