-- Desktop Mode windowing: overlapping floats, compositor title bars, work-area snap.
-- Loaded instead of default.hypr.windows when Ultimate mode is desktop.

o.window(".*", { float = true })
o.window(".*", { tag = "+default-opacity" })
-- Open as an overlapping float. 880×560 is the compositor fallback when
-- WindowService has no per-app placement for that class.
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

-- browser.lua tiles Chromium for tiling mode. Set this before that file
-- so Desktop Mode keeps Chrome as a float.
_G.omarchy_desktop_floats = true
require("default.hypr.apps")
o.window(".*", { float = true })

-- CSD by class from default/ultimate/csd-clients.json (single source of truth).
-- Keep hyprbars on foot/Qt SSD. GTK Files (Nautilus) is in that list so it is
-- not hyprbars + CSD two-row chrome.
local function repo_root()
  local omarchy = os.getenv("OMARCHY_PATH") or ""
  if omarchy ~= "" then
    return omarchy
  end
  local src = debug.getinfo(1, "S").source or ""
  src = src:gsub("^@", "")
  local root = src:match("(.+)/default/hypr/desktop%-windows%.lua$")
  return root or ""
end

local function load_csd_patterns()
  local root = repo_root()
  if root == "" then
    return {}
  end
  local file = io.open(root .. "/default/ultimate/csd-clients.json", "r")
  if not file then
    return {}
  end
  local body = file:read("*a")
  file:close()
  local patterns = {}
  for quoted in body:gmatch('"([^"]+)"') do
    if quoted ~= "classPatterns" then
      local pat = quoted:gsub("\\\\", "\\")
      patterns[#patterns + 1] = pat
    end
  end
  return patterns
end

for _, class_pat in ipairs(load_csd_patterns()) do
  -- CSD already draws its own shadow and edge. A compositor border + drop
  -- shadow on top is the dark halo around Chrome.
  -- 880×560 clips Chromium CSD: min/max fall off the right and only × remains.
  o.window(class_pat, { float = true, ["hyprbars:no_bar"] = true, no_shadow = true, border_size = 0, size = { 1200, 740 } })
end

-- Lock surfaces are not 880×560 app windows. Fullscreen per output, no hyprbars.
o.window("org.omarchy.screensaver", { float = true, fullscreen = true, ["hyprbars:no_bar"] = true })

-- Tiling mode uses 0.985 so the wallpaper shows through. That plus blur is
-- the grainy haze on every Desktop Mode window. Floats are opaque.
o.window({ tag = "default-opacity" }, { opacity = "1 1" })
o.window(".*", { opacity = "1 1" })

-- Stock ~/.config/hypr/looknfeel.lua is a copy of the tiling defaults and is
-- required AFTER this file. It restores cyan borders, gaps, and blur-off.
-- apply_desktop_look is called again from hyprland.lua after that file.
local function apply_desktop_look()
  hl.config({
    general = {
      resize_on_border = true,
      -- Windows resizes on a visible ~4px border. The Hyprland default of 15px
      -- eats clicks meant for the window behind an overlapping float.
      extend_border_grab_area = 4,
      gaps_in = 0,
      gaps_out = 0,
      border_size = 1,
      col = {
        active_border = "rgba(6a6a6aff)",
        inactive_border = "rgba(3a3a3aff)",
      },
    },
    -- Windows muscle memory is click-to-focus and click-to-raise. follow_mouse
    -- 1 focuses the window under the cursor without raising it, so a click on
    -- the exposed part of a background window does not bring it forward.
    input = {
      follow_mouse = 0,
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
      blur = {
        enabled = true,
        size = 8,
        passes = 2,
        popups = true,
        vibrancy = 0,
        noise = 0,
      },
    },
    render = {
      cm_auto_hdr = 0,
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
        bar_padding = 12,
        bar_button_padding = 8,
        bar_title_enabled = true,
        bar_text_size = 13,
        bar_text_font = "sans-serif",
        bar_text_align = "left",
        bar_buttons_alignment = "right",
        icon_on_hover = false,
        bar_blur = true,
        bar_color = "rgba(1c1c1e99)",
        ["col.text"] = "rgb(eeeeee)",
        on_double_click = "omarchy-shell window toggleMaximize 0x{:x}",
      },
    },
  })
  -- looknfeel uses windowsIn popin 87%. That is the maximize/minimize jank.
  hl.animation({ leaf = "windowsIn", enabled = false })
  hl.animation({ leaf = "windowsOut", enabled = false })
end

apply_desktop_look()
_G.omarchy_apply_desktop_look = apply_desktop_look

hl.layer_rule({ match = { namespace = "omarchy-taskbar" }, blur = true })
hl.layer_rule({ match = { namespace = "omarchy-start" }, blur = true })

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
  -- A failed plugin load must not abort the lua config. hyprland.lua
  -- requires monitors after omarchy; an error here skips the HDMI pin
  -- and this TV's preferred mode is 4K@30 (no signal).
  local ok = pcall(function()
    hl.exec_cmd("hyprctl plugin load " .. path)
  end)
  return ok
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
  -- Prefer a checkout-built .so so `omarchy dev link` + make takes effect
  -- without waiting on sudo install into /usr/lib/hyprland-plugins.
  local candidates = {}
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/hyprbars/hyprbars.so"
  end
  candidates[#candidates + 1] = "/usr/lib/hyprland-plugins/hyprbars.so"
  candidates[#candidates + 1] = "/usr/local/lib/hyprland-plugins/hyprbars.so"
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
  local candidates = {}
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/omarchy-minimize/omarchy-minimize.so"
  end
  candidates[#candidates + 1] = "/usr/lib/hyprland-plugins/omarchy-minimize.so"
  candidates[#candidates + 1] = "/usr/local/lib/hyprland-plugins/omarchy-minimize.so"
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
  -- hyprbars draws buttons right-to-left, so the user sees min / max / close.
  -- Snap layouts are maximize-hover (hover_action), drag-to-edge, and Win+Z.
  plugin.hyprbars.add_button({
    bg_color = "rgb(c42b1c)",
    fg_color = "rgb(ffffff)",
    size = 22,
    icon = "×",
    action = "omarchy-shell window close 0x{:x}",
  })
  plugin.hyprbars.add_button({
    bg_color = "rgb(c8c8c8)",
    fg_color = "rgb(1a1a1a)",
    size = 22,
    icon = "□",
    action = "omarchy-shell window toggleMaximize 0x{:x}",
    hover_action = "omarchy-shell window snapChooser 0x{:x}",
  })
  plugin.hyprbars.add_button({
    bg_color = "rgb(c8c8c8)",
    fg_color = "rgb(1a1a1a)",
    size = 22,
    icon = "–",
    action = "omarchy-shell window minimize 0x{:x}",
  })
  _G.omarchy_hyprbars_buttons = true
end

load_hyprbars()
add_hyprbars_buttons()
load_omarchy_minimize()

hl.on("hyprland.start", function()
  apply_desktop_look()
  load_hyprbars()
  add_hyprbars_buttons()
  load_omarchy_minimize()
end)

-- Start is a 440x560 card. Click-through onto the already-focused window
-- does not change active toplevel, so QML cannot see it. Bind the click
-- only while omarchy-start is mapped, skip the card and Start orb, and
-- pass the event so the window underneath still raises.
local start_clickthrough_bind = nil

local function start_click_is_on_shell_chrome(pos)
  if not pos or pos.x == nil or pos.y == nil then
    return true
  end
  local mh = 1080
  local ok, mons = pcall(function()
    return hl.get_monitors()
  end)
  if ok and type(mons) == "table" then
    for _, mon in pairs(mons) do
      if type(mon) == "table" and mon.height then
        if mon.focused or mon.focus then
          mh = mon.height
          break
        end
        mh = mon.height
      end
    end
  end
  if pos.y >= mh - 48 then
    return true
  end
  local card_y = mh - 48 - 560
  if pos.x >= 8 and pos.x < 448 and pos.y >= card_y and pos.y < mh - 48 then
    return true
  end
  return false
end

hl.on("layer.opened", function(layer)
  if not layer or layer.namespace ~= "omarchy-start" or start_clickthrough_bind then
    return
  end
  start_clickthrough_bind = hl.bind("mouse:272", function()
    local pos = hl.get_cursor_pos()
    if start_click_is_on_shell_chrome(pos) then
      return
    end
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell dismissOutside"))
  end, { description = "Dismiss Start click-through", mouse = true, non_consuming = true })
end)

hl.on("layer.closed", function(layer)
  if not layer or layer.namespace ~= "omarchy-start" or not start_clickthrough_bind then
    return
  end
  start_clickthrough_bind:unbind()
  start_clickthrough_bind = nil
end)
