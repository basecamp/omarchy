local wezterm = require("wezterm")
local bindings = require("bindings")
local theme = require("theme")
local config = wezterm.config_builder()

-- Edit keybinds in ~/.config/wezterm/bindings.lua
bindings.apply_to_config(config)

-- Theme to be updated by theme switcher
theme.apply_to_config(config)

-- Font
config.font = wezterm.font("JetBrains Mono")
config.font_size = 9

-- Window
config.window_close_confirmation = "NeverPrompt"
config.window_decorations = "NONE"
config.window_padding = {
  left = 14,
  right = 14,
  top = 14,
  bottom = 14,
}
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false

return config
