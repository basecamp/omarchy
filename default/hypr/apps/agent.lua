-- omarchy-agent gives every agent terminal the same app-id, so this
-- floats the keybinding, the menu, and a crash diagnosis alike. The size
-- scales with the monitor instead of pinning one pixel count everywhere.
o.window("org\\.omarchy\\.agent", { float = true, center = true, size = { "(monitor_w*3/5)", "(monitor_h*4/5)" } })
