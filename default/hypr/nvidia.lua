local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"

-- These detectors read cached sysfs IDs rather than shelling out to lspci.
-- lspci reads PCI config space, which resumes a runtime-suspended GPU, and on a
-- hybrid laptop that wake alone outlasts Hyprland's 1.5s config reload budget.
--
-- WebKitGTK's DMA-BUF renderer does not work against NVIDIA's EGL driver on
-- Wayland, which is the backend envs.lua selects. GTK apps on the system
-- WebKitGTK die with "Error 71 (Protocol error) dispatching to Wayland
-- display"; apps bundling their own WebKit (Tauri apps, AppImages) abort with
-- "Could not create GBM EGL display". The fallback renderer costs some
-- compositing performance, but is what makes these apps run at all. Set only
-- where we have already committed to NVIDIA's driver stack, so nouveau cards
-- keep the accelerated path -- they render through Mesa, which is unaffected.
if o.shell_succeeds(o.shell_quote(nvidia)) then
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
  elseif o.shell_succeeds(o.shell_quote(nvidia_without_gsp)) then
    hl.env("NVD_BACKEND", "egl")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
  end
end
