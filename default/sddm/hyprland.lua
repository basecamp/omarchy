-- Minimal Hyprland config for the SDDM Wayland greeter.
-- SDDM starts the greeter itself after the compositor is ready.

-- Type the password with the same keyboard layout as the user session. The
-- greeter runs without bootstrap.lua, so reach Omarchy's Lua modules by hand.
-- Guard every step: a greeter that errors out locks everyone out, so any
-- failure falls back to Hyprland's default layout instead.
local input = {}
if package and require and pcall then
  package.path = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
    .. "/?.lua;" .. package.path
  local ok, keyboard = pcall(require, "default.hypr.keyboard")
  if ok and type(keyboard) == "table" then
    input = {
      kb_layout = keyboard.kb_layout,
      kb_variant = keyboard.kb_variant,
      kb_options = keyboard.kb_options,
    }
  end
end

hl.config({
  input = input,

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },

  animations = {
    enabled = false,
  },
})
