local active_border_color = "rgba(798186ee) rgba(caccccee)"
local inactive_border_color = "rgb(1e1e1e)"

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
