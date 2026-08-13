# Common tweaks

This is a collection of common tailorings to the Omarchy setup. Know that it might occasionally be necessary for system updates to restore certain configs to their original condition. If this happens, your changes won't be lost, but put in a `.bak` file in the same directory.

If you screw something up, you can restore individual configs to their original setup via _Update > Config_ in the Omarchy menu. If you _really_ screw everything up, you can reset all configs via `omarchy-reinstall`.

### Reveal all tray icons all the time

By default, tray icons, like Dropbox, 1password, or Steam, are hidden behind the tray expander icon. If you'd like to have them exposed all the time, you can change the `group/tray-expander` line to `tray` in Waybar's `~/.config/waybar/config.jsonc` (access via _Setup > Config > Waybar_).

### Rounded window corners

Omarchy's default design is one of square corners, but if you like to soften that up a bit, you can change `~/.config/hypr/looknfeel.conf` so rounding is no longer commented out:

```
decoration {
    # Use round window corners
    rounding = 8
}
```

### Remove window gaps

On laptop displays, some people prefer to not to waste any pixels on window gaps (or even a top bar, which you can toggle off with `Super + Shift + Space`). You can remove all gaps by removing the comments in this section of `~/.config/hypr/looknfeel.conf`:

```
general {
    # No gaps between windows or borders
    gaps_in = 0
    gaps_out = 0
    border_size = 0
}
```
