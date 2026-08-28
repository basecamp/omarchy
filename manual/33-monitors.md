# Monitors

Omarchy assumes you're running on a 2x-capable retina-class display by default. This is what you need to get those nice, crisp programmer fonts. It's what almost all new premium laptops with high-resolution screens are optimized for. It's what you'd want to run on a 27" 5K [Apple Studio Display](https://www.apple.com/studio-display/)/[ProArt PA27JCV](https://www.asus.com/us/displays-desktops/monitors/proart/proart-display-5k-pa27jcv/)/[Samsung S9](https://www.samsung.com/us/computing/monitors/5k/27-viewfinity-s9-5k-monitor-with-thunderbolt-4-matte-display-and-smart-features-ls27c900panxza/)/[Kuycon G27P](https://kuycon.us/monitors/G27P/) or 32" 6K [Apple XDR](https://www.apple.com/pro-display-xdr/)/[ProArt PA32QCV](https://www.asus.com/displays-desktops/monitors/proart/proart-display-6k-pa32qcv/)/[Kuycon G32P](https://kuycon.us/monitors/G32P/).

But if you're not running a display with a PPI of 218 or above, you'll want to change the monitor settings. For example, if you have a 27" or 32" 4K, you can use fractional scaling by opening `~/.config/hypr/monitors.lua` (via _Setup > Monitors_ in the Omarchy menu) and switching to the recommendation for that combo:

```lua
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1.6
```

If you're using a 1080p or 1440p display, you'll probably just want to use 1x scaling, so you can use:

```lua
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1
```

Changes to `GDK_SCALE` apply to applications started after the change (and GTK only honors whole numbers, so keep it at the nearest integer of your monitor scale). So make sure you quit the windows that you have that are oversized after the change (or close all windows with `Ctrl + Alt + Del`!).

You can also quickly step through the major monitor scaling ratios (1x, 1.25x, 1.6x, 2x, 3x, 4x) using `Super + /` to go higher and `Super + Alt + /` to go lower. If you have the default configuration, these changes will also persist past reboot.

### Making text bigger or smaller

Monitor scaling changes the size of everything. If all you want is bigger or smaller _text_, there's a single knob for that:

```
omarchy display text size 14
```

That takes a pixel size between 9 and 20, and moves the Omarchy shell, GTK applications, and your terminal together, so the whole desktop stays in proportion. Run it without an argument to see where you're at, and `omarchy display text size reset` to go back to the default. Foot is the one straggler: it has no way to reload its config, so running terminals keep their old size until you open a new one.

### Extending and mirroring laptop displays

When you connect an external screen to your laptop, the display is automatically extended. But you can change that to mirroring instead using _Trigger > Hardware_ in the Omarchy menu or `Super + Ctrl + Alt + Delete`. This is especially helpful if that external screen is a projector, and you want to show something while working.

When you're extending, closing the lid on the laptop will automatically turn off the internal screen. Opening the lid will turn it back on. You can also control this manually using _Trigger > Hardware_ in the Omarchy menu or `Super + Ctrl + Delete`.

### Arranging multiple screens

Hyprland works great with multiple screens. Read more about how to lay them out in [the Hyprland monitor documentation](https://wiki.hypr.land/Configuring/Basics/Monitors/). You can [bind specific workspaces to specific monitors](https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/) as well. In Omarchy, these rules go in `~/.config/hypr/monitors.lua` as `hl.monitor` entries — the file ships with commented examples for pinning a specific monitor to a resolution, position, and rotation.

You can also checkout [Hyprmon](https://github.com/erans/hyprmon/), if you'd like a TUI to help you with the positioning of multiple screens.

### Rotating a screen

Portrait screens, and screens on an arm that swivels, need a rotation. Open the Display panel and pick one of `0°`, `90°`, `180°`, `270°` under _Rotation_; it applies to the screen you're focused on and is saved to that screen's rule in `~/.config/hypr/monitors.lua`, so it comes back after a reboot.

From the terminal:

```bash
omarchy hyprland monitor rotate 90
omarchy hyprland monitor rotate 0 --monitor DP-3
```

Run it without a rotation to print the current one. A mirrored screen stays mirrored when you rotate it; `--no-flipped` stops the mirroring.

### When screens overlap

Changing a screen's scale or rotation changes how much room it takes up, but screens pinned to explicit positions in `monitors.lua` don't move to make space. They end up overlapping, which is what Hyprland's _"Your monitor layout is set up incorrectly"_ warning means.

Rotating from the Display panel moves the other screens clear first, so they never overlap even briefly. If a layout does end up overlapping — after a scale change, or a screen coming back on a different port — you can settle it yourself:

```bash
omarchy hyprland monitor tidy check
omarchy hyprland monitor tidy
```

Add `--dry-run` to see what it would move first. Screens are only ever moved clear of something they overlap, along the axis they're already arranged on; gaps are left alone, since a gap isn't an error and closing one would shove screens you positioned deliberately. If you'd rather place screens entirely by hand, `omarchy hyprland monitor rotate --no-tidy` leaves the positions alone.

### HDR

If a screen's EDID says it can do HDR, the Display panel shows an _HDR_ switch for it at the top right, and hovering it tells you the peak brightness that screen reports. Screens that can't do HDR don't get the switch at all.

Turning it on puts the screen into 10-bit wide-colour HDR using the luminance values the screen itself advertises, so there's usually nothing to tune. If you've already set luminances by hand in `monitors.lua`, they're kept.

```bash
omarchy hyprland monitor hdr           # what's the current state?
omarchy hyprland monitor hdr on
omarchy hyprland monitor hdr off --monitor DP-1
```

#### HDR and brightness

Most screens lock their own brightness control while they're in HDR, and drive the panel from the HDR tone curve instead. They'll still accept a brightness change and report the new number back afterwards, so nothing can tell you it didn't take — the picture simply doesn't change.

So with HDR on, the Display panel's Brightness slider moves the knob that does work: how bright ordinary, non-HDR content is within the HDR range. It reads as a percentage like it always did, labelled _Adjusts SDR brightness_. Turn it down if HDR video looks right but your terminal and web pages look washed out; turn it up if they look dim next to it. The brightness keys still drive the backlight for the screens where that does something.

From the terminal, the same control in nits:

```bash
omarchy hyprland monitor hdr --sdr-brightness 250
```

100% on the slider is the brightness your screen can hold across the whole panel, not its peak, because peak brightness only applies to small highlights — push plain white past that and the screen dims itself as its brightness limiter kicks in.

### Controlling brightness

Monitor brightness is controlled by the dedicated function keys for brightness up/down. If you hold down shift while pressing these, you'll go to maximum or minimum brightness. The keys control the display you're focused on, so external monitors that speak DDC/CI are adjusted the same way as the laptop screen.

### Apple Displays

If you're using an Apple display, the regular keyboard brightness keys will also automatically work, if you're focused on the Apple display. This is done through the `asdcontrol` command.

Note that if you're using an Apple 6K XDR display, you may see a phantom screen in your `hyprctl monitors` listing. You can turn this off with something like `hl.monitor({ output = "DP-2", disabled = true })` via _Setup > Monitors_.

On Intel machines, you should be connecting to Apple displays using a regular Thunderbolt cable. On other machines without Thunderbolt, you'll typically have to use a [DP + USB-A -> USB-C cable](https://www.amazon.com/dp/B0BNX7MS6N) to make it work.
