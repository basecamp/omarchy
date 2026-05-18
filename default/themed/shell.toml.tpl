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
# State alphas used by every interactive surface in the kit (Button,
# Toggle, TextField, etc.). Foreground-tinted unless noted.
border-width        = 1     # idle 1px border on inputs and bordered buttons
focus-border-width  = 3     # accent ring on Tab focus
idle-border-alpha   = 0.4   # alpha for the idle 1px foreground border
hot-fill-alpha      = 0.08  # cursor / hover fill
selected-fill-alpha = 0.18  # selected / active / current fill
pressed-fill-alpha  = 0.22  # button pressed
focus-fill-alpha    = 0.22  # accent fill behind Tab focus ring

[font]
# base-size is the rem root for the type scale. Every Style.font.<token>
# derives from it (e.g. body = base, subtitle ≈ base * 1.083,
# heading ≈ base * 1.333). Clamped 11..13 by the shell — row heights are
# fixed until we ship matching spacing tokens, so growth would clip.
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
