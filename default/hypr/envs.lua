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
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Use XCompose file.
hl.env("XCOMPOSEFILE", paths.home .. "/.XCompose")

-- Propagate OMARCHY_PATH and PATH to processes spawned by Hyprland (keybinds,
-- dispatchers, autostart). hyprctl setenv doesn't reach the env captured for
-- bind exec at config-load time, so omarchy-dev-link reaches this via
-- hyprctl reload re-running envs.lua with the new paths.omarchy_path.
hl.env("OMARCHY_PATH", paths.omarchy_path)

-- Prepend $OMARCHY_PATH/bin to PATH, deduping any prior occurrence so
-- reloads don't accumulate duplicates.
local bin_dir = paths.omarchy_path .. "/bin"
local current_path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
local kept = {}
for entry in current_path:gmatch("[^:]+") do
  if entry ~= bin_dir then
    table.insert(kept, entry)
  end
end
table.insert(kept, 1, bin_dir)
hl.env("PATH", table.concat(kept, ":"))

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
