return {
  foreground = "{{ foreground }}",
  background = "{{ background }}",
  cursor_bg = "{{ cursor }}",
  cursor_border = "{{ cursor }}",
  cursor_fg = "{{ background }}",
  selection_fg = "{{ selection_foreground }}",
  selection_bg = "{{ selection_background }}",
  ansi = {
    "{{ color0 }}", "{{ color1 }}", "{{ color2 }}", "{{ color3 }}",
    "{{ color4 }}", "{{ color5 }}", "{{ color6 }}", "{{ color7 }}",
  },
  brights = {
    "{{ color8 }}", "{{ color9 }}", "{{ color10 }}", "{{ color11 }}",
    "{{ color12 }}", "{{ color13 }}", "{{ color14 }}", "{{ color15 }}",
  },
  tab_bar = {
    background = "{{ background }}",
    active_tab = {
      bg_color = "{{ accent }}",
      fg_color = "{{ background }}",
    },
    inactive_tab = {
      bg_color = "{{ background }}",
      fg_color = "{{ foreground }}",
    },
    inactive_tab_hover = {
      bg_color = "{{ color0 }}",
      fg_color = "{{ foreground }}",
    },
    new_tab = {
      bg_color = "{{ background }}",
      fg_color = "{{ foreground }}",
    },
    new_tab_hover = {
      bg_color = "{{ color0 }}",
      fg_color = "{{ foreground }}",
    },
  },
}
