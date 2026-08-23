local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"
local hybrid_gpu = paths.omarchy_path .. "/bin/omarchy-hw-hybrid-gpu-sysfs"

-- These detectors read cached sysfs IDs rather than shelling out to lspci.
-- lspci reads PCI config space, which resumes a runtime-suspended GPU, and on a
-- hybrid laptop that wake alone outlasts Hyprland's 1.5s config reload budget.
if o.shell_succeeds(o.shell_quote(nvidia)) then
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

    -- On hybrid-GPU systems the iGPU drives the display, and apps like
    -- Chromium deliberately skip the NVIDIA device and decode video on the
    -- iGPU. Forcing the NVIDIA VA-API driver breaks their hardware decode
    -- entirely, so let libva pick the driver per device instead.
    if not o.shell_succeeds(o.shell_quote(hybrid_gpu)) then
      hl.env("LIBVA_DRIVER_NAME", "nvidia")
    end
  elseif o.shell_succeeds(o.shell_quote(nvidia_without_gsp)) then
    hl.env("NVD_BACKEND", "egl")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  end
end
