-- Window and layer rules for the Omarchy Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell; the bar settings panel
-- is a regular Hyprland window via Quickshell's FloatingWindow.

-- Keep the bar instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, no_anim = true, animation = "none" })

-- Launcher, image selector, emoji picker, and clipboard overlays should also pop without animation.
hl.layer_rule({ match = { namespace = "^(omarchy-menu|omarchy-launcher|omarchy-image-selector|omarchy-emoji-picker|omarchy-clipboard-picker)$" }, no_anim = true, animation = "none" })

-- Bar settings floats centered with a sensible default size instead of
-- tiling — it's a transient dialog, not a workspace surface.
o.window({
  class = "^org.quickshell$",
  title = "^Omarchy Bar Settings$",
}, {
  float = true,
  center = true,
  size = { 760, 620 },
})

-- Dev gallery is the main shell workbench; open it maximized like
-- SUPER+ALT+F so component previews have the whole workspace.
o.window({ class = "^org.quickshell$", title = "^Omarchy shell – dev gallery$" }, { maximize = true })

-- Per-widget settings dialog opens as a smaller FloatingWindow off the
-- bar settings panel; keep it floating with its own default size.
o.window({ class = "^org.quickshell$", title = "^Widget settings " }, { float = true })
o.window({ class = "^org.quickshell$", title = "^Widget settings " }, { size = { 380, 320 } })
