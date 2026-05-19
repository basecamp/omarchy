-- Battle.net launches under Proton; all its windows share class steam_app_battlenet.

-- The actual launcher: float-centered.
o.window({ class = "^steam_app_battlenet$", title = "^Battle\\.net$" }, {
  float = true,
  center = true,
  size = { 1280, 800 },
})

-- Installer: drop decorations and backdrop blur/shadow so the Blizzard chrome
-- isn't framed by the WM.
o.window({ class = "^steam_app_battlenet$", title = "^Battle\\.net Setup$" }, {
  decorate = false,
  no_blur = true,
  no_shadow = true,
})
