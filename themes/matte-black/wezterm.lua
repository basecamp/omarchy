-- Matte Black for WezTerm
-- License: Unspecified (assumed MIT-compatible)
-- Description: A minimal, dark theme with subtle contrast and warm highlights

local M = {}

M.colors = {
	foreground = "#bebebe",
	background = "#121212",

	cursor_bg = "#eaeaea",
	cursor_fg = "#121212",
	cursor_border = "#eaeaea",

	selection_fg = "#121212",
	selection_bg = "#333333",

	scrollbar_thumb = "#333333",
	split = "#595959",
	visual_bell = "#595959",

	ansi = {
		"#333333", -- black
		"#D35F5F", -- red
		"#FFC107", -- green (actually amber)
		"#b91c1c", -- yellow (deep red tone)
		"#e68e0d", -- blue (orange-like)
		"#D35F5F", -- magenta (same as red)
		"#bebebe", -- cyan (grey)
		"#bebebe", -- white
	},

	brights = {
		"#8a8a8d", -- bright black
		"#B91C1C", -- bright red
		"#FFC107", -- bright green
		"#b90a0a", -- bright yellow
		"#f59e0b", -- bright blue
		"#B91C1C", -- bright magenta
		"#eaeaea", -- bright cyan
		"#ffffff", -- bright white
	},

	tab_bar = {
		background = "#bebebe",

		active_tab = {
			bg_color = "#121212",
			fg_color = "#bebebe",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "#121212",
			fg_color = "#bebebe",
		},

		inactive_tab_hover = {
			bg_color = "#333333",
			fg_color = "#eaeaea",
			italic = true,
		},

		new_tab = {
			bg_color = "#bebebe",
			fg_color = "#121212",
		},

		new_tab_hover = {
			bg_color = "#8a8a8d",
			fg_color = "#121212",
			italic = true,
		},
	},
}

return M
