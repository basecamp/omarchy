local function reopen_closed_browser_tab()
  if o.active_window_has_tag("chromium-based-browser") or o.active_window_has_tag("firefox-based-browser") then
    o.send_shortcut_once("CTRL + SHIFT", "T")()
  end
end

o.bind("SUPER + Z", "Reopen closed browser tab", reopen_closed_browser_tab)
