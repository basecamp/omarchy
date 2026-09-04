# Troubleshooting

### I broke my system with an update!

First try to [rollback your system](47-system-snapshots.md) the version before your recent update. If that doesn't work, use `omarchy-debug` to share with your problem on #omarchy-help in the Discord. And if all that fails, you can reinstall the defaults configs and packages using `omarchy-reinstall`.

### Why are some apps so large on my display?

Omarchy assumes a 2x high-resolution display, which requires setting `GDK_SCALE` to 2 in `~/.config/hypr/monitors.lua`. But if you're on a 1x display, you can change `local omarchy_gdk_scale = 2` to 1 (and then restart any app that's oversized). See [the manual on monitors](33-monitors.md).

For Spotify, you can use `Ctrl + Minus` to shrink the UI (and `Ctrl + Plus` to make it bigger).

### Why isn't Caps Lock working?

In Omarchy, Caps Lock has been designated to be the xcompose key. That's how you get [quick emojis](07-hotkeys.md#quick-emojis) and [other autocompletions](07-hotkeys.md#quick-completions) done. If you really miss using Caps Lock, you can remap the xcompose key to something else by editing `~/.config/hypr/input.lua`, like setting it to the right alt key:

```
hl.config({
  input = {
    kb_options = "compose:ralt",
  },
})
```

### My Wi-Fi, Bluetooth, audio, or trackpad just stopped working

Before you reboot, try restarting the offending subsystem on its own. _Update > Hardware_ in the Omarchy menu has Wi-Fi, Bluetooth, Audio, and Trackpad, and reloading one of those clears up the majority of "it worked five minutes ago" situations — a Bluetooth headset that won't reconnect, a trackpad that went dead after a suspend, sound that vanished when you unplugged a monitor.

### Why are my external speakers not playing?

Probably because they're not set as the primary output. Click on the speaker icon on the right side of the bar, and it'll open the volume popup where you can pick the output device (and mix per-app volumes too).

### My laptop speakers sound off

On some laptops, Omarchy automatically applies a speaker tuning that corrects the built-in speakers' frequency response. `omarchy audio tuning status` tells you whether one is active on your machine, and `omarchy audio tuning off` turns it off if you'd rather hear the speakers raw.

### Why can't I login or sudo with my password?

You probably typed it wrong too many times and got locked out. If this is happening on the lock screen, you can hit `CTRL + ALT + F2` to start a new TTY where you can login as root, then run `faillock --reset --user [your-username]`. That'll reset the lockout, and you're good to go.

### Why isn't my 1Password authorization prompts for 1Password SSH Agent / CLI appearing?

This can happen for 2 reasons:

In order for the rich approval prompt to appear, Settings > Advanced > Use Hardware Acceleration must be turned on. _Note: This requires a reboot to begin working._

 ![troubleshooting-1password](images/troubleshooting-1password.webp)

Or if you haven't launched 1Password since booting up, the prompt will not appear.

### The live ISO shows the logo for a second, then reboots itself

That's `nouveau` crashing. On machines with a discrete NVIDIA GPU, the live environment's open-source driver tries to take over modesetting, chokes, and the kernel panics before the installer ever gets a chance to show up.

Add `nomodeset` to the kernel command line and it boots clean. The live ISO uses GRUB, not Limine — Limine only enters the picture once Omarchy is actually installed. At the GRUB menu, hit `e` on the Omarchy entry, find the `linux` line, add `nomodeset` to the end of it, then `Ctrl + X` to boot.

No window to hit `e`? Some ISO builds boot instantly with no visible menu. Fine — pull the USB stick, mount its FAT32 partition on another machine, and edit `boot/grub/grub.cfg` by hand. Add `nomodeset` to the `linux` line for the Omarchy entry, save, put the stick back in.

### It gets past the logo but hangs later, with `RTL_OCP_GPHY_COND` or a stuck "Wait Until Kernel Time Synchronized"

That's the second crash hiding behind the first one. The default `r8169` driver doesn't get along with some Realtek chips. Add `modprobe.blacklist=r8169,r8168` right next to `nomodeset` on the same `linux` line. You'll lose networking for the rest of the install — doesn't matter, the installer doesn't need it.

### The installed system does the same NVIDIA crash on its first boot, right after the disk password

Whatever you typed onto the GRUB line only applied to that one live-ISO boot. Limine builds its own boot entry for the installed system from scratch, with none of it — so the exact same `nouveau` crash can show up again the very first time the machine tries to boot for real, loading bar stalling out right when you were expecting a desktop.

Make it permanent: add `nomodeset` to `/etc/kernel/cmdline`, then run

```
sudo limine-mkinitcpio
```

to rebuild the boot entry with it baked in. (No shell yet? Boot the live ISO again with `nomodeset`, chroot into the installed system, and do it from there.)

And don't keep blacklisting `r8169` forever — that's a workaround, not a fix. Install `r8168-dkms` from the AUR and the Realtek chip just works, no kernel parameters required.
