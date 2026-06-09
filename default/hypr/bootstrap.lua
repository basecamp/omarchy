-- Hyprland bootstrap for Omarchy's Lua module path.

local home = os.getenv("HOME")

-- Load generated state from ~/.local/state, user modules from ~/.config, and
-- Omarchy defaults from $OMARCHY_PATH.
package.path = home
  .. "/.local/state/?.lua;"
  .. home
  .. "/.config/?.lua;"
  .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
  .. "/?.lua;"
  .. package.path
