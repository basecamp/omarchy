-- Minimal Hyprland config for the SDDM Wayland greeter.
-- SDDM starts the greeter itself after the compositor is ready.
-- Session scale lives in ~/.config/hypr/monitors.lua, which the sddm user cannot
-- read. The last persisted value is in /etc/sddm/omarchy-monitor-scale.
hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },

  animations = {
    enabled = false,
  },
})

local omarchy_monitor_scale = "auto"
local scale_file = os.getenv("OMARCHY_SDDM_MONITOR_SCALE") or "/etc/sddm/omarchy-monitor-scale"
local scale_handle = io.open(scale_file, "r")
if scale_handle then
  local value = (scale_handle:read("*l") or ""):match("^%s*(.-)%s*$")
  scale_handle:close()
  if value == "auto" then
    omarchy_monitor_scale = "auto"
  else
    local n = tonumber(value)
    if n and n >= 1 and n <= 4 then
      omarchy_monitor_scale = n
    end
  end
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
