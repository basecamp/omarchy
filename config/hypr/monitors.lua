-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Do not use mode = "preferred" as the desktop default. That string is the
-- EDID preferred DTD. On an HDMI TV it is often 3840x2160@30 — a movie timing
-- the compositor will set and this panel will not lock. Apply ranks modes the
-- way a PC does: 4K only when UHD is advertised at >= 50 Hz; a TV with only
-- cinema 4K gets 1080p60 so the glass lights up on plug-in.
local apply = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin/omarchy-hyprland-monitor-apply"
local emit = io.popen(apply .. " --emit-lua")
local body = emit and emit:read("*a") or ""
if emit then
  emit:close()
end
if body:match("hl%.monitor") then
  assert(load(body))()
  return
end

-- Connector list was empty at parse (DRM not ready). Hyprland still needs a
-- monitor statement; omarchy-hyprland-monitor-apply runs again from the
-- monitor watcher and replaces this once the EDID is readable.
local omarchy_monitor_scale = "auto"
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale, bitdepth = 8 })

local omarchy_gdk_scale = 1
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
