local paths = require("default.hypr.paths")
local require_optional = require("default.hypr.require_optional")

-- GUM environment variables for styling purposes.
require_optional.module("omarchy.current.theme.gum_env")

-- Cursor size.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Use XCompose file.
hl.env("XCOMPOSEFILE", paths.home .. "/.XCompose")

-- hyprctl setenv doesn't reach keybind dispatcher env; use hl.env.
hl.env("OMARCHY_PATH", paths.omarchy_path)

-- Prepend only in dev-link mode, matching default/bash/env-bootstrap. On a
-- production install /usr/share/omarchy/bin holds symlinks for the `omarchy`
-- package's binaries alone, so putting it first shadows the complete /usr/bin
-- with an incomplete copy -- and the dispatcher scans its own directory, so
-- every omarchy-* command another package ships to /usr/bin (omarchy-debug,
-- omarchy-debug-idle, omarchy-upload-log from omarchy-settings;
-- omarchy-nvim-setup, omarchy-nvim-refresh from omarchy-nvim) loses its route
-- for the whole graphical session.
local omarchy_path = paths.omarchy_path:gsub("/+$", "")
if omarchy_path ~= "/usr/share/omarchy" then
  local bin_dir = omarchy_path .. "/bin"
  local kept = {}
  for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
    if entry ~= bin_dir then table.insert(kept, entry) end
  end
  table.insert(kept, 1, bin_dir)
  hl.env("PATH", table.concat(kept, ":"))
end

-- Hardware-specific environment.
require("default.hypr.nvidia")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
