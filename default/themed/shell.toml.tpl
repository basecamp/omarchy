# Omarchy shell surfaces. Colors derive from colors.toml; sizes and the
# typographic scale come from the keys below. Themes can ship
# themes/<name>/shell.toml to override any individual key.

[bar]
# Alpha companions (where present) range from 0 (invisible) to 1 (opaque).
background       = "{{ background }}"
background-alpha = 1.0
text             = "{{ foreground }}"
# Modules calling attention to themselves (recording, voxtype, alerts, updates)
active           = "{{ color1 }}"
# Cross-axis size in px. size-horizontal is the height of top/bottom bars;
# size-vertical is the width of left/right bars.
size-horizontal  = 26
size-vertical    = 28

[controls]
# Shared state tokens for interactive control chrome (buttons, dropdowns,
# tab strips, etc).

# Normal: idle control chrome.
normal-color        = "{{ foreground }}"
normal-fill-alpha   = 0.04
normal-border-width = 1
normal-border-alpha = 0.4

# Hover-cursor: mouse hover and the panel keyboard cursor.
hover-cursor-color        = "{{ foreground }}"
hover-cursor-fill-alpha   = 0.08
hover-cursor-border-width = 1
hover-cursor-border-alpha = 0.25

# Focus: Qt activeFocus. Mirror the hover-cursor values by default so
# mouse hover, keyboard cursor, and tab focus all read as the same state
# — themes that want focus to stand out override these four lines.
focus-color        = "{{ foreground }}"
focus-fill-alpha   = 0.08
focus-border-width = 1
focus-border-alpha = 0.25

# Selected: persistent chosen/current state.
selected-color        = "{{ foreground }}"
selected-fill-alpha   = 0.18
selected-border-width = 0
selected-border-alpha = 1.0

# Momentary fills.
pressed-fill-alpha   = 0.22
selection-fill-alpha = 0.35

[spacing]
# Multiplies shared margins, gaps, and padding. See docs/omarchy-shell.md#spacing.
scale = 1.0

[font]
# base-size is the rem root for the type scale. Every Style.font.<token>
# derives from it (e.g. body = base, subtitle ≈ base * 1.083,
# heading ≈ base * 1.333). Clamped 11..13 by the shell because some
# row heights remain fixed, so larger type can clip.
base-size = 12
# Per-token overrides, in px. Uncomment any to pin a specific size without
# affecting the rest of the scale. Useful for stylistic emphasis (a
# minimalist theme that wants a bigger heading without scaling everything).
# caption       = 10
# body-small    = 11
# body          = 12
# subtitle      = 13
# title         = 14
# heading       = 16
# display       = 24
# display-large = 28
# icon-small    = 11
# icon          = 14
# icon-large    = 18

[popups]
# Shared by every bar flyout (dropdowns, OSD, popup cards).
background       = "{{ background }}"
background-alpha = 1.0
text             = "{{ foreground }}"
border           = "{{ accent }}"
border-alpha     = 1.0

[tooltip]
# Hover tooltips across the bar, panels, and buttons. background-alpha of
# 0.97 mirrors the legacy hard-coded tooltip opacity.
background       = "{{ background }}"
background-alpha = 0.97
text             = "{{ foreground }}"
border           = "{{ foreground }}"
border-alpha     = 1.0

[notifications]
background       = "{{ background }}"
background-alpha = 1.0
text             = "{{ foreground }}"
# Conventionally matches the Hyprland active-window border
border           = "{{ accent }}"
border-alpha     = 1.0
countdown        = "{{ accent }}"

[app-launcher]
# Same six tokens as [menu], applied to the app launcher overlay. Alpha
# companions go from 0 (invisible) to 1 (opaque). Defaults mirror [menu]:
# subtle foreground-tinted fill on the selected row, no visible border,
# accent-colored text. background-alpha of 0.95 mirrors the legacy
# hard-coded card translucency.
background                = "{{ background }}"
background-alpha          = 0.95
text                      = "{{ foreground }}"
border                    = "{{ foreground }}"
border-alpha              = 1.0
selected-background       = "{{ foreground }}"
selected-background-alpha = 0.08
selected-text             = "{{ accent }}"
selected-border           = "{{ foreground }}"
selected-border-alpha     = 0.25

[menu]
# Cards, rows, and selected-row treatment. Alpha companions (where present)
# go from 0 (invisible) to 1 (opaque). Defaults mirror the panel keyboard
# cursor: a subtle foreground-tinted fill on the selected row, no visible
# border, accent-colored text. Override any of these per-theme.
background                = "{{ background }}"
background-alpha          = 1.0
text                      = "{{ foreground }}"
border                    = "{{ foreground }}"
border-alpha              = 1.0
selected-background       = "{{ foreground }}"
selected-background-alpha = 0.08
selected-text             = "{{ accent }}"
selected-border           = "{{ foreground }}"
selected-border-alpha     = 0.25

[image-picker]
# Carousel-style picker. background-alpha sets the scrim opacity behind
# the picker; unselected-border-alpha softens carousel slices that aren't
# the current selection. Defaults preserve the legacy hard-coded behavior.
background              = "{{ background }}"
background-alpha        = 0.5
text                    = "{{ foreground }}"
selected-border         = "{{ accent }}"
selected-border-alpha   = 1.0
unselected-border       = "{{ foreground }}"
unselected-border-alpha = 0.28
