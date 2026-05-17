-- Window and layer rules for the Omarchy Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell; the bar settings panel
-- is a regular Hyprland window via Quickshell's FloatingWindow.

-- Keep the bar and menu instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "omarchy-menu" }, no_anim = true, animation = "none" })

-- Image selector and emoji picker overlays should also pop without animation.
hl.layer_rule({ match = { namespace = "omarchy-image-selector" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "omarchy-emoji-picker" }, no_anim = true, animation = "none" })

-- Bar settings floats centered with a sensible default size instead of
-- tiling — it's a transient dialog, not a workspace surface.
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Bar Settings$" }, float = true })
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Bar Settings$" }, center = true })
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Bar Settings$" }, size = { 760, 620 } })

-- Per-widget settings dialog opens as a smaller FloatingWindow off the
-- bar settings panel; keep it floating with its own default size.
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Widget settings " }, float = true })
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Widget settings " }, size = { 380, 320 } })
