-- Window and layer rules for the Omarchy Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell; the settings panel is
-- a regular Hyprland window via Quickshell's FloatingWindow.

-- Keep the menu instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "omarchy-menu" }, no_anim = true, animation = "none" })

-- Image selector overlay should also pop without animation.
hl.layer_rule({ match = { namespace = "omarchy-image-selector" }, no_anim = true, animation = "none" })

-- Settings panel floats centered with a sensible default size instead of
-- tiling — it's a transient dialog, not a workspace surface.
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Settings$" }, float = true })
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Settings$" }, center = true })
hl.window_rule({ match = { class = "^org.quickshell$", title = "^Omarchy Settings$" }, size = { 960, 700 } })
