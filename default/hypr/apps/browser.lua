-- Browser types.
hl.window_rule({ match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" }, tag = "+chromium-based-browser" })
hl.window_rule({ match = { class = "([fF]irefox|zen|librewolf)" }, tag = "+firefox-based-browser" })
hl.window_rule({ match = { tag = "chromium-based-browser" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "firefox-based-browser" }, tag = "-default-opacity" })

-- Video apps: remove chromium browser tag so they don't get opacity applied.
hl.window_rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-chromium-based-browser" })
hl.window_rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-default-opacity" })

-- Force chromium-based browsers into a tile to deal with --app bug.
hl.window_rule({ match = { tag = "chromium-based-browser" }, tile = true })

-- Only a subtle opacity change, but not for video sites.
hl.window_rule({ match = { tag = "chromium-based-browser" }, opacity = "1.0 0.97" })
hl.window_rule({ match = { tag = "firefox-based-browser" }, opacity = "1.0 0.97" })

-- Hide the screen-sharing notification bar (the "Hide" button on it is broken on Wayland).
hl.window_rule({ match = { title = ".*is sharing.*" }, workspace = "special silent" })
