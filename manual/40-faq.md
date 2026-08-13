# FAQ

### How do I switch between keyboard layouts?

Edit your `~/.config/hypr/input.lua` file and add this to switch between layouts on `Left Alt + Right Alt`:

```
hl.config({
  input = {
    -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
    kb_layout = "us,fr",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
  },
})
```

The bar will automatically show your current keyboard layout once you have multiple layouts configured (and you can click it to switch too).

### How do I change the clock format to 12-hour?

Right-click the clock in the bar to cycle through the common formats, including the 12-hour ones. You can also set the format directly:

```
omarchy bar set omarchy.clock format "dddd h:mm AP"
```

This will display Sunday 10:55 AM.

### How do I change where screenshots or screenrecordings are saved?

If you want screenshots to be saved to `~/Pictures/Screenshots` instead of just `~/Pictures`, you can add this to a file under `~/.config/uwsm/env.d/` (like `~/.config/uwsm/env.d/capture`):

```
export OMARCHY_SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
```

You can do the same for screenrecordings using `OMARCHY_SCREENRECORD_DIR`.

Just remember to create the directoy you want to save to and restart Omarchy for this to take effect.

### How do I get the speakers + webcam working on my Apple Studio Display?

You'd think that it should all work just plugging in USB C, but unfortunately that isn't the case. The solution I've found to make it work reliably is using [the WJESOG DisplayPort + USB-A => USB-C cable](https://www.amazon.com/WJESOG-DisplayPort-Adapter-Converter-Thunderbolt/dp/B0BNX7MS6N/). Then speakers and webcam work like a charm.

Remember that you have built-in brightness control in Omarchy for the Apple Displays (both Studio and XDR) using the regular keyboard brightness buttons.

### How do I get rid of all the extra software?

If you don't want programs like Obsidian or LibreOffice or any of the other preinstalled stuff, you can very easily remove it.

Run _Remove > Package_ to see every package that's installed. Then you can select any package you'd like to remove with tab, and start removing everything you've selected with return.

And you can use _Remove > Web App_ from the Omarchy menu to remove any of the preinstalled web apps you don't want.

Or run _Remove > Preinstalls_ to sweep out all the preinstalled extras — web apps, TUIs, and optional applications — in one go.

---

For errors and broken bits, see [the Troubleshooting section](39-troubleshooting.md).
