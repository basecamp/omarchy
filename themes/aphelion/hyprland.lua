local active_border_color = { colors = { "rgba(eef3faee)", "rgba(7c8ca8ee)" }, angle = 90 }
local inactive_border_color = "rgba(161b24aa)"

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

  decoration = {
    rounding = 6,
    rounding_power = 3,
    shadow = {
      enabled = true,
      range = 22,
      render_power = 3,
      offset = "0 6",
      color = "rgba(00000099)",
      color_inactive = "rgba(00000055)",
    },
  },
})
