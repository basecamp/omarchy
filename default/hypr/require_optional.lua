-- Require a module only when it can be found on package.path.
-- Errors inside existing modules still surface normally from module().
-- Use safe() for user overrides that must not abort the rest of the config.

local M = {}

function M.module(module)
  if package.searchpath(module, package.path) then
    return require(module)
  end
end

-- Load when present; log and continue if the module itself errors. Used by the
-- user hyprland.lua so a broken monitors/input file cannot strand the session
-- without keybindings (#9721).
function M.safe(module)
  if not package.searchpath(module, package.path) then
    return
  end

  local ok, err = pcall(require, module)
  if not ok then
    print("[Omarchy Config Error] Failed to load " .. module .. ": " .. tostring(err))
  end
end

return M
