local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Dynamic theme colors
local theme_path = os.getenv("HOME") .. "/.config/omarchy/current/theme/wezterm.lua"
local f = io.open(theme_path, "r")
if f then
  f:close()
  config.colors = dofile(theme_path)
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
