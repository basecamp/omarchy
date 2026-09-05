o.window("^(Bitwarden)$", { no_screen_share = true, tag = "+floating-window" })

-- The browser-extension popouts (passkey prompts, vault popouts) are matched by
-- the extension ID alone: Chromium names these windows "<browser>-<extid>-Default",
-- so a chrome-only prefix misses Brave, Edge, Vivaldi and the rest, leaving the
-- popout tiled and too small to use.
o.window(".*nngceckbapebfimnlniiiahkandclblb.*", {
  no_screen_share = true,
  tag = "+floating-window",
})
