local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"
local nvidia_only = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-only"

-- These detectors read cached sysfs IDs rather than shelling out to lspci.
-- lspci reads PCI config space, which resumes a runtime-suspended GPU, and on a
-- hybrid laptop that wake alone outlasts Hyprland's 1.5s config reload budget.
if o.shell_succeeds(o.shell_quote(nvidia)) then
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")

    -- Pinning VA-API to the NVIDIA driver is only correct when NVIDIA is the
    -- only GPU. On a hybrid laptop the iGPU normally drives the panel, so
    -- forcing the whole session to decode on the dGPU sends every video frame
    -- across the PRIME boundary to reach an iGPU-composited display, which
    -- flickers while scrolling. Left unset, libva picks the driver matching
    -- whichever GPU each app actually renders on.
    if o.shell_succeeds(o.shell_quote(nvidia_only)) then
      hl.env("LIBVA_DRIVER_NAME", "nvidia")
    end

    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  elseif o.shell_succeeds(o.shell_quote(nvidia_without_gsp)) then
    hl.env("NVD_BACKEND", "egl")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  end
end
