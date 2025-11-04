local wezterm = require("wezterm")

local config = {}

-- Automatically reload config when files change
config.automatically_reload_config = true

-- Load theme
local theme_file = wezterm.home_dir .. "/.config/omarchy/current/theme/wezterm.lua"
local f = io.open(theme_file, "r")

if f ~= nil then
	f:close()
	local ok, theme = pcall(dofile, theme_file)
	if ok and type(theme) == "table" then
		for k, v in pairs(theme) do
			config[k] = v
		end
	elseif ok and type(theme) == "string" then
		config.color_scheme = theme
	else
		wezterm.log_warn("theme.lua did not return a valid color_scheme")
		config.color_scheme = "Catppuccin Mocha"
	end
else
	config.color_scheme = "Catppuccin Mocha"
end

-- Font
config.font = wezterm.font_with_fallback({
	"CaskaydiaMono Nerd Font",
})
config.font_size = 9.0
config.window_frame = { font_size = 9.0 }

-- Window
config.window_padding = {
	left = 14,
	right = 14,
	top = 14,
	bottom = 14,
}

config.window_decorations = "NONE"
config.window_close_confirmation = "NeverPrompt"

-- Keybindings
config.keys = {
	{ key = "Insert", mods = "CTRL", action = wezterm.action.CopyTo("Clipboard") },
	{ key = "Insert", mods = "SHIFT", action = wezterm.action.PasteFrom("Clipboard") },
}

-- Aesthetics
config.cursor_blink_rate = 0
config.audible_bell = "Disabled"

-- Minimal Tab bar styling
config.enable_tab_bar = true
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

return config
