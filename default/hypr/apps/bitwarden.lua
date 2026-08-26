o.window("^(Bitwarden)$", { no_screen_share = true, tag = "+floating-window" })

-- Chromium prefixes extension popout classes with the browser name and can
-- append the popup path. Match Bitwarden's stable extension ID instead.
o.window(".*nngceckbapebfimnlniiiahkandclblb.*", {
  float = true,
  max_size = { 480, 650 },
  no_blur = true,
  no_screen_share = true,
})
