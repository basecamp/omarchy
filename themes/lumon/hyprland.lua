local active_border_color = "rgb(f2fcff)"
local active_shadow_color = "rgb(6fb8e3)"
local inactive_border_color = "rgba(30486099)"
local inactive_shadow_color = "rgba(30486077)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
    gaps_in = 8,
    gaps_out = 16,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    shadow = {
      enabled = true,
      range = 16,
      render_power = 4,
      color = active_shadow_color,
      color_inactive = inactive_shadow_color,
    },
  },
})
