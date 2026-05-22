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
# Cross-axis size at font base-size 12. size-horizontal is the height of
# top/bottom bars; size-vertical is the width of left/right bars. With
# scale-with-font enabled, these grow/shrink with [font] base-size.
scale-with-font  = true
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
# `scale` multiplies shared margins, gaps, padding, controls, and panel
# dimensions; components keep their proportions. With scale-with-font
# enabled, those dimensions grow/shrink with [font] base-size too. Per-token
# overrides (in px) below pin individual values without affecting the rest
# of the scale. Uncomment any to tune a specific surface.
scale = 1.0
scale-with-font = true
# xxs                       = 2
# xs                        = 3
# sm                        = 4
# md                        = 6
# lg                        = 8
# xl                        = 10
# xxl                       = 12
# xxxl                      = 14
# huge                      = 18
# control-gap               = 8
# control-padding-x         = 10
# control-padding-y         = 6
# input-padding-y           = 7
# control-height            = 28
# popup-row-height          = 28
# row-gap                   = 8
# row-padding-x             = 12
# label-gap                 = 4
# panel-gap                 = 14
# panel-padding             = 18
# popup-padding             = 14
# dropdown-width            = 240
# searchable-dropdown-width = 260
# number-field-width        = 120
# searchable-popup-min-height = 220

[font]
# base-size is the rem root for the type scale. Every Style.font.<token>
# derives from it (e.g. body = base, subtitle ≈ base * 1.083,
# heading ≈ base * 1.333). The shell only floors this at 1px; increase it
# as much as you want.
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

[launcher]
# Same six tokens as [menu], applied to the launcher overlay. Alpha
# companions go from 0 (invisible) to 1 (opaque). scrim is the full-screen
# dim layer behind the card; background is the card itself. Defaults
# mirror [menu] with the card at 0.95 to preserve the legacy translucency.
background                = "{{ background }}"
background-alpha          = 0.95
text                      = "{{ foreground }}"
border                    = "{{ foreground }}"
border-alpha              = 1.0
scrim                     = "{{ background }}"
scrim-alpha               = 0.5
selected-background       = "{{ foreground }}"
selected-background-alpha = 0.08
selected-text             = "{{ accent }}"
selected-border           = "{{ foreground }}"
selected-border-alpha     = 0.25

[menu]
# Cards, rows, and selected-row treatment. Alpha companions (where present)
# go from 0 (invisible) to 1 (opaque). scrim is the full-screen dim layer
# behind the card. Clipboard and emojis inherit these tokens.
background                = "{{ background }}"
background-alpha          = 1.0
text                      = "{{ foreground }}"
border                    = "{{ foreground }}"
border-alpha              = 1.0
scrim                     = "{{ background }}"
scrim-alpha               = 0.5
selected-background       = "{{ foreground }}"
selected-background-alpha = 0.08
selected-text             = "{{ accent }}"
selected-border           = "{{ foreground }}"
selected-border-alpha     = 0.25

[polkit]
# Polkit authentication prompt (sudo/password dialogs). scrim is the
# darkening layer behind the card; background is the card itself.
# text-error tints the lock icon, password text, and placeholder when
# authentication fails. border-alpha applies to both border and
# border-error (the two states are mutually exclusive in time).
background       = "{{ background }}"
background-alpha = 1.0
text             = "{{ foreground }}"
text-error       = "{{ color1 }}"
border           = "{{ accent }}"
border-error     = "{{ color1 }}"
border-alpha     = 1.0
scrim            = "{{ background }}"
scrim-alpha      = 0.5
# accent is the lock-icon glyph color + text-selection tint.
accent           = "{{ accent }}"

[lock]
# Lock screen password input. background/background-alpha control the
# centered input field card; border/border-active/border-error cycle
# through idle, typing/authenticating, and wrong-password states.
# border-alpha applies to all three border states (they are mutually
# exclusive in time).
background       = "{{ background }}"
background-alpha = 0.8
text             = "{{ foreground }}"
text-error       = "{{ color1 }}"
border           = "{{ foreground }}"
border-active    = "{{ accent }}"
border-error     = "{{ color1 }}"
border-alpha     = 1.0
# selection is the text-selection tint inside the input field.
selection        = "{{ accent }}"
selection-alpha  = 0.45

[image-picker]
# Carousel-style picker. The picker has no card surface, so `scrim` is
# the full-screen wash. Per-slice dim overlays and text outlines on top
# of the scrim track the foundational background color directly.
# unselected-border-alpha softens carousel slices that aren't selected.
scrim                   = "{{ background }}"
scrim-alpha             = 0.5
text                    = "{{ foreground }}"
selected-border         = "{{ accent }}"
selected-border-alpha   = 1.0
unselected-border       = "{{ foreground }}"
unselected-border-alpha = 0.28
