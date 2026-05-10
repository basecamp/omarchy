local active_border_color = "rgb(dcd7ba)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
    },
  },
})

-- Kanagawa backdrop is too strong for default opacity.
hl.window_rule({ match = { tag = "terminal" }, opacity = "0.98 0.95" })
