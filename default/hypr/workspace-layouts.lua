-- Restore workspace layouts saved by omarchy-hyprland-workspace-layout-toggle.
-- Mirror toggles.lua: put the layouts directory on package.path and require bare
-- filenames. A module prefix of omarchy.workspace-layouts needs a state root on
-- package.path; user hyprland.lua files that predate bootstrap extraction only
-- put ~/.config and $OMARCHY_PATH there, so every reload after a toggle raised
-- "module not found" (#9664). Directory-on-path stops depending on the entrypoint.

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local layouts_dir = paths.state_home .. "/omarchy/workspace-layouts"
package.path = layouts_dir .. "/?.lua;" .. package.path

require_all.files(layouts_dir, nil, { reload = true })
