local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Font
config.font_size = 18

-- Window
config.window_close_confirmation = "NeverPrompt"
config.window_decorations = "NONE"
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.colors = {
  background = "black",
  cursor_bg = "black",
}
config.window_background_opacity = 1.0
config.enable_tab_bar = false

return config
