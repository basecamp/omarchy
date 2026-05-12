-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can override with -default-opacity tag).
hl.window_rule({ match = { class = ".*" }, tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
hl.window_rule({
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_focus = true,
})

-- App-specific tweaks (may remove default-opacity tag).
require("default.hypr.apps")

-- Apply default opacity after apps have had a chance to opt out.
hl.window_rule({ match = { tag = "default-opacity" }, opacity = "0.97 0.9" })
