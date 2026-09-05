-- Restore workspace layouts saved by omarchy-hyprland-workspace-layout-toggle.

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

-- The saved files call o.workspace_mode, so it has to exist before they load.
require("default.hypr.workspace-modes")

local layouts_dir = paths.state_home .. "/omarchy/workspace-layouts"

-- The directory is found through XDG_STATE_HOME but the files are loaded by
-- module name, and bootstrap only puts ~/.local/state on the search path. A
-- state home anywhere else would list the saved layouts and then fail to require
-- them, or load same-named ones from under the home directory instead.
package.path = paths.state_home .. "/?.lua;" .. package.path

require_all.files(layouts_dir, "omarchy.workspace-layouts", { reload = true })
