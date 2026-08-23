# Common tweaks

This is a collection of common tailorings to the Omarchy setup. Know that it might occasionally be necessary for system updates to restore certain configs to their original condition. If this happens, your changes won't be lost, but put in a `.bak` file in the same directory.

If you screw something up, you can restore individual configs to their original setup via _Update > Config_ in the Omarchy menu. If you _really_ screw everything up, you can reset all configs via `omarchy-reinstall`.

### Hide or rearrange tray icons

By default, tray icons, like Dropbox, 1password, or Steam, sit behind the tray expander arrow, which reveals them when you hover it. Drag an icon within the open drawer to rearrange it. Right-click the expander arrow to open the tray manager: the Show System Icons switch hides or reveals them all at once, and each icon's row toggles just that one. You can also drag any bar widget onto the tray to store it in the drawer, and drag it back out whenever you want it on the bar full-time.

### Rounded window corners

Omarchy's default design is one of square corners, but if you like to soften that up a bit, you can change `~/.config/hypr/looknfeel.lua` so rounding is no longer commented out:

```
hl.config({
  decoration = {
    -- Use round window corners.
    rounding = 8,
  },
})
```

### Remove window gaps

On laptop displays, some people prefer not to waste any pixels on window gaps (or even a top bar, which you can toggle off with `Super + Shift + Space`). You can toggle all gaps and borders off with `Super + Shift + Backspace`, or remove them permanently by removing the comments in this section of `~/.config/hypr/looknfeel.lua`:

```
hl.config({
  general = {
    -- No gaps between windows or borders.
    gaps_in = 0,
    gaps_out = 0,
    border_size = 0,
  },
})
```
