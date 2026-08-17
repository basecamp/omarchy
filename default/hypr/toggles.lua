local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local toggles_dir = paths.state_home .. "/omarchy/toggles/hypr"
package.path = toggles_dir .. "/?.lua;" .. package.path

require_all.files(toggles_dir, nil, { reload = true })

-- Settings chosen in the Input panel are generated outside ~/.config/hypr so
-- the panel never rewrites a user's hand-maintained Lua. Load them last so the
-- visible controls describe the effective values they own.
local input_panel = paths.state_home .. "/omarchy/hypr/input.lua"
local input_file = io.open(input_panel, "r")
if input_file then
  input_file:close()
  dofile(input_panel)
end

require("default.hypr.workspace-layouts")
