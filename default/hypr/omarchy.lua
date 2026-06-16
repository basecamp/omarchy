-- Omarchy Hyprland setup: helpers, defaults, and current theme overrides.

require("default.hypr.helpers")

-- Use Omarchy defaults, but don't edit these directly.
require("default.hypr.autostart")
if _G.omarchy_default_bindings ~= false then
  require("default.hypr.bindings.media")
  require("default.hypr.bindings.clipboard")
  require("default.hypr.bindings.tiling-v2")
  require("default.hypr.bindings.utilities")
  require("default.hypr.bindings.applications")
end
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.input")
require("default.hypr.windows")

-- Current theme overrides.
require("default.hypr.require_optional").module("omarchy.current.theme.hyprland")
