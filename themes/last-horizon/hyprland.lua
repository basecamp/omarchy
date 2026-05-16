local active_border_color = "rgba(8a8588ee) rgba(e2dddcee)"
local inactive_border_color = "rgba(584e51aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },
  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})
