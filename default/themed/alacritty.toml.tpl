[colors.primary]
background = "{{ background }}"
foreground = "{{ foreground }}"

[colors.cursor]
text = "{{ background }}"
cursor = "{{ cursor }}"

[colors.vi_mode_cursor]
text = "{{ background }}"
cursor = "{{ cursor }}"

[colors.search.matches]
foreground = "{{ background }}"
background = "{{ yellow }}"

[colors.search.focused_match]
foreground = "{{ background }}"
background = "{{ red }}"

[colors.footer_bar]
foreground = "{{ background }}"
background = "{{ foreground }}"

[colors.selection]
text = "{{ selection_foreground }}"
background = "{{ selection_background }}"

[colors.normal]
black = "{{ bg }}"
red = "{{ red }}"
green = "{{ green }}"
yellow = "{{ yellow }}"
blue = "{{ blue }}"
magenta = "{{ purple }}"
cyan = "{{ cyan }}"
white = "{{ fg }}"

[colors.bright]
black = "{{ muted }}"
red = "{{ bright_red }}"
green = "{{ bright_green }}"
yellow = "{{ bright_yellow }}"
blue = "{{ bright_blue }}"
magenta = "{{ bright_purple }}"
cyan = "{{ bright_cyan }}"
white = "{{ bright_fg }}"
