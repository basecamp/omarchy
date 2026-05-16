# Omarchy shell colors. Defaults derive from colors.toml; themes can ship
# themes/<name>/shell.toml to override individual keys.

[bar]
background = "{{ background }}"
text       = "{{ foreground }}"
# Modules calling attention to themselves (recording, voxtype, alerts, updates)
active     = "{{ color1 }}"

[popups]
# Shared by every bar flyout. Body text inside flyouts is not separately
# themable — it follows [bar].text.
background = "{{ background }}"
border     = "{{ foreground }}"

[notifications]
background = "{{ background }}"
text       = "{{ foreground }}"
# Conventionally matches the Hyprland active-window border
border     = "{{ accent }}"
countdown  = "{{ accent }}"

[menu]
background = "{{ background }}"
text       = "{{ foreground }}"
selected   = "{{ accent }}"

[image-picker]
# Drawn at ~70% alpha as a scrim
background        = "{{ background }}"
text              = "{{ foreground }}"
selected-border   = "{{ accent }}"
# Drawn at ~28% alpha
unselected-border = "{{ foreground }}"
