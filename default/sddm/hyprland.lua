-- Minimal Hyprland config for the SDDM Wayland greeter.
-- SDDM starts the greeter itself after the compositor is ready.

-- The greeter is its own Hyprland instance, started by sddm-helper instead of
-- the user session, so it never runs default/hypr/bootstrap.lua. Set up just
-- enough of the module path to share the session's layout resolution: with no
-- input block Hyprland falls back to its built-in "us" default, and a password
-- set under any other layout cannot be typed at the login prompt.
package.path = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/?.lua;" .. package.path

local keyboard = require("default.hypr.keyboard")

hl.config({
  input = {
    kb_layout = keyboard.layout,
    kb_variant = keyboard.variant,
    kb_options = keyboard.options,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },

  animations = {
    enabled = false,
  },
})
