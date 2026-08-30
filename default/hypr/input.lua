-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

-- The layout resolution lives in default/hypr/keyboard.lua so the SDDM greeter
-- can share it and type passwords with the same layout as the session.
local keyboard = require("default.hypr.keyboard")

hl.config({
  input = {
    kb_layout = keyboard.kb_layout,
    kb_variant = keyboard.kb_variant,
    kb_model = "",
    kb_options = keyboard.kb_options,
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll nicely in the terminal.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
