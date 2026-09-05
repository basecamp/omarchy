local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"
local nvidia_drives_display = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-drives-display"

-- These detectors read cached sysfs IDs rather than shelling out to lspci.
-- lspci reads PCI config space, which resumes a runtime-suspended GPU, and on a
-- hybrid laptop that wake alone outlasts Hyprland's 1.5s config reload budget.
--
-- Naming NVIDIA here points every GL and VA-API client in the session at that
-- card, so it has to be the card actually driving the screen. On a hybrid laptop
-- the panel hangs off the integrated GPU while the discrete card sits in runtime
-- suspend, and setting these there means the first GL application to start wakes
-- it and holds it awake. Having an NVIDIA GPU is not the same as rendering on it.
if o.shell_succeeds(o.shell_quote(nvidia)) and o.shell_succeeds(o.shell_quote(nvidia_drives_display)) then
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  elseif o.shell_succeeds(o.shell_quote(nvidia_without_gsp)) then
    hl.env("NVD_BACKEND", "egl")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  end
end
