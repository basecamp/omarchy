-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
--
-- Bindings first, each via require_optional.safe: a syntax/runtime error in
-- monitors or input must not abort evaluation before keybindings load, or the
-- session starts with no Super shortcuts and no recovery path (#9721).
local require_optional = require("default.hypr.require_optional")
require_optional.safe("hypr.bindings")
require_optional.safe("hypr.monitors")
require_optional.safe("hypr.input")
require_optional.safe("hypr.looknfeel")
require_optional.safe("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
