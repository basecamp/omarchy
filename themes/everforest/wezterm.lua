-- Everforest Dark Hard (WezTerm)
-- Ported from Kitty theme by Sainnhe Park
-- License: MIT
-- Upstream: https://github.com/ewal/kitty-everforest/blob/master/themes/everforest_dark_hard.conf

local M = {}

M.colors = {
	foreground = "#d3c6aa",
	background = "#272e33",

	cursor_bg = "#d3c6aa",
	cursor_fg = "#2e383c",
	cursor_border = "#d3c6aa",

	selection_fg = "#9da9a0",
	selection_bg = "#464e53",

	scrollbar_thumb = "#374145",
	split = "#4f5b58",
	visual_bell = "#e69875",

	ansi = {
		"#343f44", -- black
		"#e67e80", -- red
		"#a7c080", -- green
		"#dbbc7f", -- yellow
		"#7fbbb3", -- blue
		"#d699b6", -- magenta
		"#83c092", -- cyan
		"#859289", -- white
	},

	brights = {
		"#868d80", -- bright black
		"#e67e80", -- bright red
		"#a7c080", -- bright green
		"#dbbc7f", -- bright yellow
		"#7fbbb3", -- bright blue
		"#d699b6", -- bright magenta
		"#83c092", -- bright cyan
		"#9da9a0", -- bright white
	},

	tab_bar = {
		background = "#2e383c", -- tab_bar_background

		active_tab = {
			bg_color = "#272e33", -- active_tab_background
			fg_color = "#d3c6aa", -- active_tab_foreground
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#374145", -- inactive_tab_background
			fg_color = "#9da9a0", -- inactive_tab_foreground
		},

		inactive_tab_hover = {
			bg_color = "#464e53",
			fg_color = "#d3c6aa",
			italic = true,
		},

		new_tab = {
			bg_color = "#2e383c",
			fg_color = "#9da9a0",
		},

		new_tab_hover = {
			bg_color = "#374145",
			fg_color = "#d3c6aa",
			italic = true,
		},
	},
}

return M
