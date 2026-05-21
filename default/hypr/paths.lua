-- Shared path constants for Omarchy's Hyprland Lua modules.
-- Lua files loaded with require() have separate local scopes, so modules that
-- need these paths import this table instead of repeating os.getenv() lookups.

local home = os.getenv("HOME")

-- /etc/omarchy.conf wins over process env so dev-link survives stale sessions.
local function read_dev_link_omarchy_path()
  local f = io.open("/etc/omarchy.conf", "r")
  if not f then return nil end
  local value
  for line in f:lines() do
    local v = line:match('^%s*export%s+OMARCHY_PATH=%s*"?([^"\n]+)"?')
    if v and #v > 0 then value = v end
  end
  f:close()
  return value
end

local omarchy_path = read_dev_link_omarchy_path()
  or os.getenv("OMARCHY_PATH")
  or "/usr/share/omarchy"

return {
  home = home,
  config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config"),
  state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state"),
  omarchy_path = omarchy_path,
}
