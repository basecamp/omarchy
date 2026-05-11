-- Float Steam.
hl.window_rule({ match = { class = "steam" }, float = true })
hl.window_rule({ match = { class = "steam", title = "Steam" }, center = true })
hl.window_rule({ match = { class = "steam.*" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "steam.*" }, opacity = "1 1" })
hl.window_rule({ match = { class = "steam", title = "Steam" }, size = { 1100, 700 } })
hl.window_rule({ match = { class = "steam", title = "Friends List" }, size = { 460, 800 } })
hl.window_rule({ match = { class = "steam" }, idle_inhibit = "fullscreen" })
