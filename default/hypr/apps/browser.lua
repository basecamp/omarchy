-- Browser tags and styling.
-- Hyprland matches class with RE2 FullMatch, so bare browser ids alone miss
-- Chromium --app webapp classes of the form <browser>-<host>__<path>-Default.
-- The optional (-.+-Default) suffix covers those without loosening bare ids.
o.window("((google-)?[cC]hrom(e|ium)|[bB]rave(-browser|-origin)?|[mM]icrosoft-edge|Vivaldi-stable|helium)(-.+-Default)?", { tag = "+chromium-based-browser" })
o.window("([fF]irefox|zen|librewolf)", { tag = "+firefox-based-browser" })
o.window({ tag = "chromium-based-browser" }, { tag = "-default-opacity", tile = true, opacity = "1.0 0.985" })
o.window({ tag = "firefox-based-browser" }, { tag = "-default-opacity", opacity = "1.0 0.985" })

-- Video apps: remove chromium browser tag so they don't get opacity applied.
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-chromium-based-browser" })
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-default-opacity" })

-- Hide screen sharing notification windows.
o.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
