# Omarchy on...

### Apple M1/M2 chips

[Asahi Alarm](https://asahi-alarm.org/) is a version of Arch for Apple M1/M2 computers built on top of [Asahi Linux](https://asahilinux.org/). You can get Omarchy running on top of that with some effort. See [the user-driven guide](https://github.com/omarchy-mac/omarchy-mac).

### Apple Virtual Machine

You can also install Omarchy inside a Parallels VM. Quite the cumbersome process, but there's [a user-driven guide](https://github.com/basecamp/omarchy/discussions/452) for that too.

### QEMU/KVM with SPICE

Omarchy automatically enables two-way text clipboard sharing when it is installed in a QEMU/KVM guest with a SPICE virtio channel. In virt-manager, use a SPICE display, add a SPICE agent channel named `com.redhat.spice.0`, and leave clipboard sharing enabled. The first graphical login installs `omarchy-vdagent`, which connects the SPICE daemon directly to Hyprland's Wayland clipboard through `wl-copy` and `wl-paste`.

The stock `spice-vdagent` session process is X11-only, so Omarchy masks that session process inside matching guests while leaving the system `spice-vdagentd` daemon unchanged. Do not add the daemon's `-X` flag: current Omarchy sessions pass the normal logind active-session check, and `-X` can break the guest's uinput tablet and make its cursor disappear.

Clipboard transfer is text-only. Check the guest side with:

```bash
systemctl --user status omarchy-vdagent
journalctl --user -u omarchy-vdagent
```

The Wayland agent is adapted from [`omarchy-arm-vdagent`](https://github.com/ggalancs/omarchy-arm-utm) and the investigation shared in [discussion #7956](https://github.com/basecamp/omarchy/discussions/7956).

### VirtualBox

VirtualBox is a popular VM runner. [You can run Omarchy inside that too](https://github.com/basecamp/omarchy/discussions/176). But performance probably won't be great.

### VMware Workstation on Windows 11

Another popular VM runner for Windows. [Omarchy has been setup inside of that as well](https://github.com/basecamp/omarchy/discussions/572).

### Steam Deck

The Steam Deck runs on Arch, which means you can run Omarchy on your Steam Deck. Altynbek Orumbayev has [a full setup script and explanation on how to do it](https://github.com/aorumbayev/deckarchy). How cool is that!

### NixOS

Omarchy is really Arch + Hyprland, but Henry Sipp has [ported the essence of the setup to NixOS](https://github.com/henrysipp/omarchy-nix). So if you've been nix-pilled, here's a good starting point. It may or may not stay up-to-date with the latest Omarchy changes, but it's pretty cool none the less!

### Something else!

If you're trying to get Omarchy running on a configuration that isn't the default, you should join the #omarchy-on-other channel on [our community Discord](https://discord.gg/tXFUdasqhY).
