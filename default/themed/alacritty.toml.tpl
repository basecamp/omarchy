[colors.primary]
background = "{{ bg }}"
foreground = "{{ fg }}"

[colors.cursor]
text = "{{ bg }}"
cursor = "{{ bright_fg }}"

[colors.vi_mode_cursor]
text = "{{ bg }}"
cursor = "{{ bright_fg }}"

[colors.search.matches]
foreground = "{{ bg }}"
background = "{{ yellow }}"

[colors.search.focused_match]
foreground = "{{ bg }}"
background = "{{ red }}"

[colors.footer_bar]
foreground = "{{ bg }}"
background = "{{ fg }}"

[colors.selection]
text = "{{ selection_foreground }}"
background = "{{ selection_background }}"

[colors.normal]
black = "{{ bg }}"
red = "{{ red }}"
green = "{{ green }}"
yellow = "{{ yellow }}"
blue = "{{ blue }}"
magenta = "{{ magenta }}"
cyan = "{{ cyan }}"
white = "{{ fg }}"

[colors.bright]
black = "{{ muted }}"
red = "{{ bright_red }}"
green = "{{ bright_green }}"
yellow = "{{ bright_yellow }}"
blue = "{{ bright_blue }}"
magenta = "{{ bright_magenta }}"
cyan = "{{ bright_cyan }}"
white = "{{ bright_fg }}"
