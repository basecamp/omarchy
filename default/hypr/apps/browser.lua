-- Browser tags and styling.
o.window("((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)", { tag = "+chromium-based-browser" })
o.window("([fF]irefox|librewolf|^zen$|^zen-)", { tag = "+firefox-based-browser" })
-- Desktop Mode is overlapping floats. Tiling Chromium here fills the work
-- area, so Chrome's CSD □ is a no-op on an already-covering window.
local chromium_style = { tag = "-default-opacity", opacity = "1.0 0.985" }
if not _G.omarchy_desktop_floats then
  chromium_style.tile = true
end
o.window({ tag = "chromium-based-browser" }, chromium_style)
o.window({ tag = "firefox-based-browser" }, { tag = "-default-opacity", opacity = "1.0 0.985" })

-- Video apps: remove chromium browser tag so they don't get opacity applied.
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-chromium-based-browser" })
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-default-opacity" })

-- Hide screen sharing notification windows.
o.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
