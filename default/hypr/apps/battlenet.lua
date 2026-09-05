-- Battle.net launches under Proton; all its windows share class steam_app_battlenet.

-- Main client: tile it like every other app. Omarchy used to float it at
-- 1280x800; Wine/Qt then sent an X11 ConfigureRequest that parked that dialog
-- off the left edge (x ~= -2 * monitor width on 1080p with GDK_SCALE=2).
-- Ignore those configure requests so the tiled size sticks.
--
-- Do not tile the login or setup windows: resizing the Qt shell during login
-- destroys the CEF webview (empty logo box, WM_DESTROY on webViewWindow).

o.window({ class = "^steam_app_battlenet$", title = "^Battle\\.net$" }, {
  tile = true,
  suppress_event = "maximize x11configurerequest",
})

o.window({ class = "^steam_app_battlenet$", title = "^Battle\\.net Login$" }, {
  float = true,
  center = true,
  suppress_event = "maximize x11configurerequest",
})

-- Installer: drop decorations and backdrop blur/shadow so the Blizzard chrome
-- isn't framed by the WM. Same X11 configure trap as the launcher.
o.window({ class = "^steam_app_battlenet$", title = "^Battle\\.net Setup$" }, {
  float = true,
  center = true,
  decorate = false,
  no_blur = true,
  no_shadow = true,
  suppress_event = "maximize x11configurerequest",
})

-- Dropdowns and CEF children are empty-title 0x0 XWayland windows.
-- Without stay_focused + min_size they close as soon as they open.
o.window({ class = "^steam_app_battlenet$", title = "^$" }, {
  float = true,
  stay_focused = true,
  min_size = { 1, 1 },
})
