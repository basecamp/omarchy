-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Drop cached omarchy modules so hyprctl reload re-reads them from disk.
for k in pairs(package.loaded) do
  if k:match("^default%.hypr") or k:match("^hypr%.") then
    package.loaded[k] = nil
  end
end

-- Load user modules from ~/.config and Omarchy defaults from $OMARCHY_PATH.
package.path = os.getenv("HOME")
  .. "/.config/?.lua;"
  .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
  .. "/?.lua;"
  .. package.path

-- All Omarchy default setups
require("default.hypr.omarchy")

-- Change your own setup in these files and override defaults.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
