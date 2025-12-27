local wezterm = require("wezterm")
local act = wezterm.action
local bindings = {}

function bindings.apply_to_config(config)
  config.keys = {
    {
      key = "T",
      mods = "CTRL|SHIFT",
      action = act.SpawnTab("DefaultDomain"),
    },
    {
      key = "L",
      mods = "CTRL|SHIFT",
      action = act.ActivateTabRelative(1),
    },
    {
      key = "H",
      mods = "CTRL|SHIFT",
      action = act.ActivateTabRelative(-1),
    },
    {
      key = "K",
      mods = "CTRL|SHIFT",
      action = act.MoveTabRelative(1),
    },
    {
      key = "J",
      mods = "CTRL|SHIFT",
      action = act.MoveTabRelative(-1),
    },
    {
      key = "W",
      mods = "CTRL|SHIFT",
      action = act.CloseCurrentTab({ confirm = true }),
    },
  }
end

return bindings
