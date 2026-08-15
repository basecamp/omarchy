-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

o.window(".*", { suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can override with -default-opacity tag).
o.window(".*", { tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
o.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

-- Java AWT tooltips/menus are real X11 windows that reuse the parent class
-- and title themselves win0, win1, ... A class-only tile/maximize rule
-- stretches them over the whole client. Float and keep them unfocused.
o.window({
  class = ".*",
  title = "^win[0-9]+$",
  xwayland = true,
}, {
  float = true,
  no_initial_focus = true,
  no_focus = true,
  no_follow_mouse = true,
})

-- App-specific tweaks (may remove default-opacity tag).
require("default.hypr.apps")

-- Apply default opacity after apps have had a chance to opt out.
o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })
