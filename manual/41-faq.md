# FAQ

### How do I switch between keyboard layouts?

Edit your `~/.config/hypr/input.conf` file and add this to switch between layouts on `Left Alt + Right Alt`:

```
# Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
input {
    kb_layout = us,fr
    kb_options = compose:caps,grp:alts_toggle
}
```

You can even [configure Waybar to showing your current keyboard layout in the top bar](https://github.com/basecamp/omarchy/discussions/111).

### How do I change the clock format to 12-hour?

Edit your `~/.config/waybar/config.jsonc` file and replace this:

```
  "clock": {
    "format": "{:%A %H:%M}",
```

with:

```
  "clock": {
    "format": "{:%A %I:%M %p}",
```

This will display Sunday 10:55 AM.

### How do I change where screenshots or screenrecordings are saved?

If you screenshots to be saved to `~/Pictures/Screenshots` instead of just `~/Pictures`, you can open _Setup > Defaults_ via the Omarchy menu and set this:

```
export OMARCHY_SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
```

You can do the same for screenrecordings using `OMARCHY_SCREENRECORD_DIR`.

Just remember to create the directoy you want to save to and restart Omarchy for this to take effect.

### How do I get the speakers + webcam working on my Apple Studio Display?

You'd think that it should all work just plugging in USB C, but unfortunately that isn't the case. The solution I've found to make it work reliably is using [the WJESOG DisplayPort + USB-A => USB-C cable](https://www.amazon.com/WJESOG-DisplayPort-Adapter-Converter-Thunderbolt/dp/B0BNX7MS6N/). Then speakers and webcam work like a charm.

Remember that you have built-in brightness control in Omarchy for the Apple Displays (both Studio and XDR) using the regular keyboard brightness buttons.

### How do I get rid of all the extra software?

If you don't want programs like Spotify or Obsidian or any of the other preinstalled stuff, you can very easily remove it.

Run _Remove > Package_ to see every package that's installed. Then you can select any package you'd like to remove with tab, and start removing everything you've selected with return.

And you can use _Remove > Web App_ from the Omarchy menu to remove any of the preinstalled web apps you don't want.

---

For errors and broken bits, see [the Troubleshooting section](40-troubleshooting.md).
