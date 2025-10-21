-- Gruvbox Dark for WezTerm
-- Author: Pavel Pertsev
-- License: MIT/X11
-- Upstream: https://github.com/gruvbox-community/gruvbox-contrib
-- Ported from kitty/gruvbox-dark.conf

local M = {}

M.colors = {
	foreground = "#ebdbb2",
	background = "#282828",

	cursor_bg = "#bdae93",
	cursor_fg = "#665c54",
	cursor_border = "#bdae93",

	selection_fg = "#ebdbb2",
	selection_bg = "#d65d0e",

	scrollbar_thumb = "#3c3836",
	split = "#504945",
	visual_bell = "#d65d0e",

	ansi = {
		"#3c3836", -- black
		"#cc241d", -- red
		"#98971a", -- green
		"#d79921", -- yellow
		"#458588", -- blue
		"#b16286", -- magenta
		"#689d6a", -- cyan
		"#a89984", -- white
	},

	brights = {
		"#928374", -- bright black
		"#fb4934", -- bright red
		"#b8bb26", -- bright green
		"#fabd2f", -- bright yellow
		"#83a598", -- bright blue
		"#d3869b", -- bright magenta
		"#8ec07c", -- bright cyan
		"#fbf1c7", -- bright white
	},

	tab_bar = {
		background = "#282828",

		active_tab = {
			bg_color = "#d65d0e", -- active_tab_background
			fg_color = "#eeeeee", -- active_tab_foreground
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#202020", -- inactive_tab_background
			fg_color = "#ebdbb2", -- inactive_tab_foreground
		},

		inactive_tab_hover = {
			bg_color = "#3c3836",
			fg_color = "#fbf1c7",
			italic = true,
		},

		new_tab = {
			bg_color = "#282828",
			fg_color = "#ebdbb2",
		},

		new_tab_hover = {
			bg_color = "#3c3836",
			fg_color = "#fbf1c7",
			italic = true,
		},
	},
}

return M
