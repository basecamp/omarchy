# Omarchy shell colors. Defaults below derive from colors.toml. Any theme
# can ship its own shell.toml at themes/<name>/shell.toml to override
# individual keys — anything left out falls back to the values here.

[bar]
# The bar strip itself
background = "{{ background }}"
# Clock, weather, workspace numbers, indicator glyphs
text       = "{{ foreground }}"
# Module in an "active" state: screen recording, voxtype listening,
# weather alert, update available. Same color is used everywhere a
# module wants to call attention to itself.
active     = "{{ color1 }}"

[popups]
# Body fill for every flyout opened from the bar: wifi, bluetooth, audio,
# calendar, weather, control-center, notification-center, media. Body text
# inside the flyouts is not separately themable — it follows [bar].text.
background = "{{ background }}"
# 1px outline around the flyout
border     = "{{ foreground }}"

[notifications]
# Toast card body
background = "{{ background }}"
# Title and message text
text       = "{{ foreground }}"
# Card outline. Most themes match this to their Hyprland active-window
# border so notifications visually belong to the focused window.
border     = "{{ accent }}"
# Bottom countdown bar that drains while the toast is on screen
countdown  = "{{ accent }}"

[menu]
# Omarchy menu surface (the launcher-style picker invoked by the menu key)
background = "{{ background }}"
# Unhighlighted menu items
text       = "{{ foreground }}"
# Currently hovered / keyboard-selected item
selected   = "{{ accent }}"

[image-picker]
# Backdrop scrim behind the picker (the picker draws this at ~70% alpha)
background        = "{{ background }}"
# Tile labels (image filename / theme name)
text              = "{{ foreground }}"
# 3px stroke around the currently selected tile
selected-border   = "{{ accent }}"
# 1px stroke around every other tile (picker applies ~28% alpha)
unselected-border = "{{ foreground }}"
