-- Disable a Hyprland input device whose name was stored as data, not Lua.
-- Device names come from USB descriptors and must never be loaded as code.

local paths = require("default.hypr.paths")

return function(kind)
  -- Hardcoded to ~/.local/state to match omarchy-toggle-input-device and the
  -- sibling bash toggle tools, which all write there regardless of
  -- XDG_STATE_HOME.
  local file = io.open(paths.home .. "/.local/state/omarchy/toggles/hypr/" .. kind .. "-disabled-name", "r")
  if not file then
    return
  end

  local name = file:read("*l")
  file:close()

  if name and name ~= "" then
    hl.device({ name = name, enabled = false })
  end
end
