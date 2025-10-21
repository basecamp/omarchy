local M = {}

M.colors = {
	foreground = "{{ foreground }}",
	background = "{{ background }}",

	cursor_bg = "{{ cursor }}",
	cursor_fg = "{{ background }}",
	cursor_border = "{{ cursor }}",

	selection_fg = "{{ selection_foreground }}",
	selection_bg = "{{ selection_background }}",

	scrollbar_thumb = "{{ color0 }}",
	split = "{{ color8 }}",
	visual_bell = "{{ accent }}",

	ansi = {
		"{{ color0 }}",  -- black
		"{{ color1 }}",  -- red
		"{{ color2 }}",  -- green
		"{{ color3 }}",  -- yellow
		"{{ color4 }}",  -- blue
		"{{ color5 }}",  -- magenta
		"{{ color6 }}",  -- cyan
		"{{ color7 }}",  -- white
	},

	brights = {
		"{{ color8 }}",  -- bright black
		"{{ color9 }}",  -- bright red
		"{{ color10 }}", -- bright green
		"{{ color11 }}", -- bright yellow
		"{{ color12 }}", -- bright blue
		"{{ color13 }}", -- bright magenta
		"{{ color14 }}", -- bright cyan
		"{{ color15 }}", -- bright white
	},

	tab_bar = {
		background = "{{ color0 }}",

		active_tab = {
			bg_color = "{{ background }}",
			fg_color = "{{ foreground }}",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab = {
			bg_color = "{{ color0 }}",
			fg_color = "{{ color15 }}",
		},

		inactive_tab_hover = {
			bg_color = "{{ color8 }}",
			fg_color = "{{ foreground }}",
			italic = true,
		},

		new_tab = {
			bg_color = "{{ color0 }}",
			fg_color = "{{ color15 }}",
		},

		new_tab_hover = {
			bg_color = "{{ color8 }}",
			fg_color = "{{ foreground }}",
			italic = true,
		},
	},
}

return M
