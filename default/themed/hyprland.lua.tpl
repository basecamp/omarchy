local active_border_color = {{ hypr_gradient hyprland_active_border accent }}
local inactive_border_color = {{ hypr_gradient hyprland_inactive_border rgba(595959aa) }}

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
    rounding = {{ value hyprland_rounding 0 }},
    rounding_power = {{ value hyprland_rounding_power 2 }},

    shadow = {
      enabled = {{ value hyprland_shadow_enabled false }},
      range = {{ value hyprland_shadow_range 4 }},
      render_power = {{ value hyprland_shadow_render_power 3 }},
      offset = "{{ value hyprland_shadow_offset 0 0 }}",
      color = "{{ value hyprland_shadow_color rgba(1a1a1aee) }}",
      color_inactive = "{{ value hyprland_shadow_color_inactive rgba(1a1a1aee) }}",
    },
  },
})
