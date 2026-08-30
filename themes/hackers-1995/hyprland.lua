local active_border_color = { colors = { "rgba(ff6600ee)", "rgba(ffaa00ee)" }, angle = 45 }
local inactive_border_color = "rgba(113322aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },
  decoration = {
    rounding = 6,
    shadow = {
      enabled = true,
      range = 14,
      render_power = 3,
      color = "rgba(ff660040)",
      color_inactive = "rgba(00000066)",
    },
  },
  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})
