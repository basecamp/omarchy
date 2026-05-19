# Omarchy shell surfaces. Colors derive from colors.toml; sizes and the
# typographic scale come from the keys below. Themes can ship
# themes/<name>/shell.toml to override any individual key.

[bar]
background = "{{ background }}"
text       = "{{ foreground }}"
# Modules calling attention to themselves (recording, voxtype, alerts, updates)
active     = "{{ color1 }}"
# Cross-axis size in px. size-horizontal is the height of top/bottom bars;
# size-vertical is the width of left/right bars.
size-horizontal = 26
size-vertical   = 28

[style]
# Shared control state tokens. See docs/omarchy-shell.md#interactive-states.
# Colors accept palette roles (foreground/accent/urgent/background) or hex.

# Normal: idle control chrome.
normal-color        = "foreground"
normal-fill-alpha   = 0.04
normal-border-width = 1
normal-border-alpha = 0.4

# Hover-cursor: mouse hover and the panel keyboard cursor.
hover-cursor-color        = "foreground"
hover-cursor-fill-alpha   = 0.08
hover-cursor-border-width = 1
hover-cursor-border-alpha = 0.25

# Selected: persistent chosen/current state.
selected-color        = "foreground"
selected-fill-alpha   = 0.18
selected-border-width = 0
selected-border-alpha = 1.0

# Focus: Qt activeFocus; inherit hover-cursor unless intentionally different.
focus-color        = "hover-cursor"
focus-fill-alpha   = "hover-cursor"
focus-border-width = "hover-cursor"
focus-border-alpha = "hover-cursor"

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
# Shared by every bar flyout. Body text inside flyouts is not separately
# themable — it follows [bar].text.
background = "{{ background }}"
border     = "{{ accent }}"

[tooltip]
# Hover tooltips across the bar, panels, and buttons.
background = "{{ background }}"
text       = "{{ foreground }}"
border     = "{{ foreground }}"

[notifications]
background = "{{ background }}"
text       = "{{ foreground }}"
# Conventionally matches the Hyprland active-window border
border     = "{{ accent }}"
countdown  = "{{ accent }}"

[app-launcher]
# Same six tokens as [menu], applied to the app launcher overlay. Alpha
# companions go from 0 (invisible) to 1 (opaque). Defaults mirror [menu]:
# subtle foreground-tinted fill on the selected row, no visible border,
# accent-colored text.
background                = "{{ background }}"
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
text                      = "{{ foreground }}"
border                    = "{{ foreground }}"
border-alpha              = 1.0
selected-background       = "{{ foreground }}"
selected-background-alpha = 0.08
selected-text             = "{{ accent }}"
selected-border           = "{{ foreground }}"
selected-border-alpha     = 0.25

[image-picker]
# Drawn at ~70% alpha as a scrim
background        = "{{ background }}"
text              = "{{ foreground }}"
selected-border   = "{{ accent }}"
# Drawn at ~28% alpha
unselected-border = "{{ foreground }}"
