local active_border_color = {{ hypr_gradient hyprland_active_border accent }}
local inactive_border_color = {{ hypr_gradient hyprland_inactive_border rgba(595959aa) }}

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  -- decoration.glow.color is independent of general.col.active_border; without
  -- these, glow stays on Hyprland's hardcoded default (#9737).
  decoration = {
    glow = {
      color = active_border_color,
      color_inactive = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})
