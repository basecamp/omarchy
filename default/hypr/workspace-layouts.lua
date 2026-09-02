-- Restore workspace layouts saved by omarchy-hyprland-workspace-layout-toggle.
-- Mirror toggles.lua: put the layouts directory on package.path and require bare
-- filenames. A module prefix of omarchy.workspace-layouts needs state/?.lua to
-- resolve nested paths; that bootstrap entry is HOME-only and misses XDG_STATE_HOME,
-- which is how every reload after a toggle surfaced "module not found" (#9664).

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local layouts_dir = paths.state_home .. "/omarchy/workspace-layouts"
package.path = layouts_dir .. "/?.lua;" .. package.path

require_all.files(layouts_dir, nil, { reload = true })
