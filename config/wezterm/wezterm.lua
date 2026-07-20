local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.font = wezterm.font('JetBrainsMono Nerd Font')
config.font_size = 9
config.window_padding = { left = 14, right = 14, top = 14, bottom = 14 }
config.window_decorations = 'NONE'
config.audible_bell = 'Disabled'

-- Use the retro tab bar so the Omarchy theme's tab_bar colors fully apply
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

-- Dynamic Omarchy theme colors (regenerated on every `omarchy theme set`)
local theme = wezterm.home_dir .. '/.config/omarchy/current/theme/wezterm.lua'
local ok, colors = pcall(dofile, theme)
if ok and colors then
  config.colors = colors
end

return config
