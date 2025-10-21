-- Rose-Pine for WezTerm
-- License: MIT
-- Description: A soft, elegant light theme inspired by the Rose Pine palette

local M = {}

M.colors = {
	foreground = "#575279",
	background = "#faf4ed",

	cursor_bg = "#cecacd",
	cursor_fg = "#575279",
	cursor_border = "#cecacd",

	selection_fg = "#575279",
	selection_bg = "#dfdad9",

	scrollbar_thumb = "#dfdad9",
	split = "#9893a5",
	visual_bell = "#b4637a",

	ansi = {
		"#f2e9e1", -- black
		"#b4637a", -- red
		"#286983", -- green
		"#ea9d34", -- yellow
		"#56949f", -- blue
		"#907aa9", -- magenta
		"#d7827e", -- cyan
		"#575279", -- white
	},

	brights = {
		"#9893a5", -- bright black
		"#b4637a", -- bright red
		"#286983", -- bright green
		"#ea9d34", -- bright yellow
		"#56949f", -- bright blue
		"#907aa9", -- bright magenta
		"#d7827e", -- bright cyan
		"#575279", -- bright white
	},

	tab_bar = {
		background = "#575279",

		active_tab = {
			bg_color = "#fffaf3",
			fg_color = "#575279",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#fffaf3",
			fg_color = "#575279",
		},

		inactive_tab_hover = {
			bg_color = "#dfdad9",
			fg_color = "#286983",
			italic = true,
		},

		new_tab = {
			bg_color = "#575279",
			fg_color = "#faf4ed",
		},

		new_tab_hover = {
			bg_color = "#907aa9",
			fg_color = "#faf4ed",
			italic = true,
		},
	},
}

return M
