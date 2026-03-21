local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Screensaver: black background, large font, no chrome
config.colors = {
  foreground = "#a9b1d6",
  background = "#000000",
  cursor_bg = "#000000",
  cursor_fg = "#000000",
  cursor_border = "#000000",
}

config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Regular" })
config.font_size = 18

config.window_decorations = "NONE"
config.enable_tab_bar = false
config.window_background_opacity = 1.0

config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

config.window_close_confirmation = "NeverPrompt"
config.default_cursor_style = "SteadyBlock"

return config
