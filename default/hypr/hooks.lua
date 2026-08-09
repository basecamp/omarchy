-- Fire Omarchy hooks whenever Hyprland finishes reloading its config.
-- Runs only after a successful reload (syntax errors refuse the reload and
-- never emit this event). The hook command diffs the config files against the
-- last reload and reports the changed config files as its argument.
hl.on("config.reloaded", function()
  hl.exec_cmd("omarchy-hyprland-config-reloaded")
end)
