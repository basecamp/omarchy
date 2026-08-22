-- Desktop Mode windowing: overlapping windows, real maximize, border resize.
-- Loaded instead of default.hypr.windows when Ultimate mode is desktop.

o.window(".*", { float = true })
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

require("default.hypr.apps")

o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })

hl.config({
  general = {
    resize_on_border = true,
  },
  decoration = {
    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
    },
  },
  cursor = {
    hide_on_key_press = false,
  },
})
