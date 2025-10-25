-- Flexoki (Light) for WezTerm
-- Author: Kepano
-- License: MIT
-- Upstream: https://github.com/kepano/flexoki
-- Description: An inky color scheme for prose and code

local M = {}

M.colors = {
	foreground = "#100F0F",
	background = "#FFFCF0",

	cursor_bg = "#100F0F",
	cursor_fg = "#FFFCF0",
	cursor_border = "#100F0F",

	selection_fg = "#100F0F",
	selection_bg = "#CECDC3",

	scrollbar_thumb = "#E6E4D9",
	split = "#CECDC3",
	visual_bell = "#D14D41",

	ansi = {
		"#100F0F", -- black
		"#D14D41", -- red
		"#879A39", -- green
		"#D0A215", -- yellow
		"#4385BE", -- blue
		"#CE5D97", -- magenta
		"#3AA99F", -- cyan
		"#FFFCF0", -- white
	},

	brights = {
		"#6F6E69", -- bright black
		"#AF3029", -- bright red
		"#66800B", -- bright green
		"#AD8301", -- bright yellow
		"#205EA6", -- bright blue
		"#A02F6F", -- bright magenta
		"#24837B", -- bright cyan
		"#F2F0E5", -- bright white
	},

	tab_bar = {
		background = "#FFFCF0",

		active_tab = {
			bg_color = "#CECDC3",
			fg_color = "#100F0F",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#E6E4D9",
			fg_color = "#6F6E69",
		},

		inactive_tab_hover = {
			bg_color = "#CECDC3",
			fg_color = "#100F0F",
			italic = true,
		},

		new_tab = {
			bg_color = "#FFFCF0",
			fg_color = "#6F6E69",
		},

		new_tab_hover = {
			bg_color = "#E6E4D9",
			fg_color = "#100F0F",
			italic = true,
		},
	},
}

return M
