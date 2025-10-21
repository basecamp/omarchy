-- Kanagawa for WezTerm
-- Author: Tommaso Laurenzi
-- License: MIT
-- Upstream: https://github.com/rebelot/kanagawa.nvim/
-- Description: Dark colorscheme inspired by Hokusai's "The Great Wave"

local M = {}

M.colors = {
	foreground = "#dcd7ba",
	background = "#1f1f28",

	cursor_bg = "#c8c093",
	cursor_fg = "#1f1f28",
	cursor_border = "#c8c093",

	selection_fg = "#c8c093",
	selection_bg = "#2d4f67",

	scrollbar_thumb = "#2d4f67",
	split = "#363646",
	visual_bell = "#c34043",

	ansi = {
		"#16161d", -- black
		"#c34043", -- red
		"#76946a", -- green
		"#c0a36e", -- yellow
		"#7e9cd8", -- blue
		"#957fb8", -- magenta
		"#6a9589", -- cyan
		"#c8c093", -- white
	},

	brights = {
		"#727169", -- bright black
		"#e82424", -- bright red
		"#98bb6c", -- bright green
		"#e6c384", -- bright yellow
		"#7fb4ca", -- bright blue
		"#938aa9", -- bright magenta
		"#7aa89f", -- bright cyan
		"#dcd7ba", -- bright white
	},

	indexed = {
		[16] = "#ffa066",
		[17] = "#ff5d62",
	},

	tab_bar = {
		background = "#1f1f28",

		active_tab = {
			bg_color = "#1f1f28",
			fg_color = "#c8c093",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#1f1f28",
			fg_color = "#727169",
		},

		inactive_tab_hover = {
			bg_color = "#2d4f67",
			fg_color = "#dcd7ba",
			italic = true,
		},

		new_tab = {
			bg_color = "#1f1f28",
			fg_color = "#727169",
		},

		new_tab_hover = {
			bg_color = "#2d4f67",
			fg_color = "#c8c093",
			italic = true,
		},
	},
}

return M
