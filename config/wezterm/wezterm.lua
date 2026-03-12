local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Dynamic theme colors
local home_dir = wezterm.home_dir or os.getenv("HOME")
if home_dir and home_dir ~= "" then
  local theme_path = home_dir .. "/.config/omarchy/current/theme/wezterm.lua"
  local f = io.open(theme_path, "r")
  if f then
    f:close()
    local ok, colors = pcall(dofile, theme_path)
    if ok and type(colors) == "table" then
      config.colors = colors
    end
  end
end

-- Font
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Regular" })
config.font_size = 9

-- No title bar, no tab bar
config.window_decorations = "NONE"
config.enable_tab_bar = false

-- Window padding
config.window_padding = {
  left = 14,
  right = 14,
  top = 14,
  bottom = 14,
}

-- No close confirmation
config.window_close_confirmation = "NeverPrompt"

-- Cursor: steady block (no blink)
config.default_cursor_style = "SteadyBlock"

-- Clipboard: map Ctrl+Insert/Shift+Insert for Omarchy SUPER+C/V bindings
local act = wezterm.action
config.keys = {
  { key = 'Insert', mods = 'CTRL', action = act.CopyTo 'Clipboard' },
  { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' },
}

return config
