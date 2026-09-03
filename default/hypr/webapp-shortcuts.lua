-- Keyboard shortcuts for user-installed web apps.
--
-- `omarchy webapp shortcut sync` compiles the X-Omarchy-Shortcut keys from
-- ~/.local/share/applications/*.desktop into the file loaded below;
-- omarchy-webapp-install and omarchy-webapp-remove run it automatically. This
-- loads before ~/.config/hypr/bindings.lua, so a hand-written binding there
-- still overrides a generated one.

local paths = require("default.hypr.paths")

local generated = paths.state_home .. "/omarchy/webapp-shortcuts.lua"
local file = io.open(generated, "r")
if file then
  file:close()
  dofile(generated)
end
