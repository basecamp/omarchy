o.window("steam", { float = true, idle_inhibit = "fullscreen" })
-- Games launch as steam_app_<id>; FullMatch on "steam" alone never covers them,
-- so gamepad sessions (no seat activity) still fire the screensaver.
o.window("^steam_app_", { idle_inhibit = "fullscreen" })
o.window({ class = "steam", title = "Steam" }, { center = true, size = { 1100, 700 } })
o.window("steam.*", { tag = "-default-opacity", opacity = "1 1" })
o.window({ class = "steam", title = "Friends List" }, { size = { 460, 800 } })
