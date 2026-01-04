local wezterm = require('wezterm')
local config = wezterm.config_builder()

-- Dynamic theme colors
-- Import theme from symlink (Omarchy's dynamic theme system)
local theme_config = os.getenv('HOME') .. '/.config/omarchy/current/theme/wezterm.lua'
local f = io.open(theme_config, 'r')
if f ~= nil then
  io.close(f)
  dofile(theme_config)
end

-- Font
config.font = wezterm.font('JetBrainsMono Nerd Font')
config.font_size = 9.0

-- Window
config.window_padding = {
  left = 14,
  right = 14,
  top = 14,
  bottom = 14,
}
config.window_decorations = 'NONE'

-- Disable tab bar
config.enable_tab_bar = false
config.use_fancy_tab_bar = false

-- Disable scroll bar
config.enable_scroll_bar = false

-- Cursor styling
config.default_cursor_style = 'SteadyBlock'
config.cursor_blink_rate = 0

-- Keyboard bindings
config.keys = {
  {
    key = 'Insert',
    mods = 'SHIFT',
    action = wezterm.action.PasteFrom('Clipboard'),
  },
  {
    key = 'Insert',
    mods = 'CTRL',
    action = wezterm.action.CopyTo('Clipboard'),
  },
}

-- Disable confirm on close
config.window_close_confirmation = 'NeverPrompt'

return config
