-- Ristretto for WezTerm
-- License: Unspecified (assumed MIT-compatible)
-- Description: A warm, espresso-inspired color scheme with soft highlights

local M = {}

M.colors = {
	foreground = "#e6d9db",
	background = "#2c2525",

	cursor_bg = "#c3b7b8",
	cursor_fg = "#2c2525",
	cursor_border = "#c3b7b8",

	selection_fg = "#e6d9db",
	selection_bg = "#403e41",

	scrollbar_thumb = "#403e41",
	split = "#595959",
	visual_bell = "#595959",

	ansi = {
		"#72696a", -- black
		"#fd6883", -- red
		"#adda78", -- green
		"#f9cc6c", -- yellow
		"#f38d70", -- blue
		"#a8a9eb", -- magenta
		"#85dacc", -- cyan
		"#e6d9db", -- white
	},

	brights = {
		"#948a8b", -- bright black
		"#ff8297", -- bright red
		"#c8e292", -- bright green
		"#fcd675", -- bright yellow
		"#f8a788", -- bright blue
		"#bebffd", -- bright magenta
		"#9bf1e1", -- bright cyan
		"#f1e5e7", -- bright white
	},

	tab_bar = {
		background = "#404040",

		active_tab = {
			bg_color = "#f9cc6c",
			fg_color = "#2c2525",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#2c2525",
			fg_color = "#e6d9db",
		},

		inactive_tab_hover = {
			bg_color = "#403e41",
			fg_color = "#f1e5e7",
			italic = true,
		},

		new_tab = {
			bg_color = "#404040",
			fg_color = "#e6d9db",
		},

		new_tab_hover = {
			bg_color = "#595959",
			fg_color = "#f9cc6c",
			italic = true,
		},
	},
}

return M
