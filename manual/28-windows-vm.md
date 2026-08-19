# Windows VM

Omarchy offers an easy way to run Windows through a Docker VM. You can install it using _Install > Windows_ from the Omarchy menu (`Super + Space`).

Your machine needs KVM virtualization for this, which most do — but it's sometimes switched off in the BIOS, and the installer will tell you if that's the case. You'll also want the disk space: whatever you give Windows, plus about 10GB for the image itself.

The installer asks how much RAM, how many CPU cores, and how much disk to hand over (64GB or more is the sensible floor), then for a Windows username and password. Leave those blank and you get `docker` / `admin`. The download takes a while — 10-15 minutes is normal — and you can follow the progress in the browser at `http://127.0.0.1:8006`.

 ![windows-vm](images/windows-vm.webp)

## Using it

Once it's installed, launch _Windows_ from the app launcher. That starts the VM if it isn't already running and connects you over RDP, full screen. Give it 15-30 seconds on a cold start.

The RDP session carries sound, your microphone, and a shared clipboard, so copying text between Linux and Windows just works. The resolution follows your window, and Omarchy passes your display scaling through, so it's not a blurry mess on a HiDPI screen.

When you close the RDP window, the VM shuts down automatically. If you'd rather leave it running — say you've got something working away in there — launch it with `omarchy windows vm launch --keep-alive` instead.

The rest of the controls are on the same command:

```bash
omarchy windows vm status    # is it running?
omarchy windows vm stop      # shut it down
omarchy windows vm launch    # start and connect
```

## Sharing files

The directory `~/Windows` in your home directory is automatically shared with the VM. Put files there if you want them accessible to Windows. The VM has no access to any other part of your file system, so you're safe from anything nasty on the Windows side. Its own virtual disk lives in `~/.windows`.

The VM's ports are bound to localhost only, so nothing on your network can reach the Windows machine.

## Limits and licensing

There's no GPU passthrough with this setup, so it's not suitable for gaming or video editing. It's a great way to run Microsoft Office or whatever else you absolutely must have.

The version installed is Windows 11 Pro, unactivated. You'll need your own license key to use the gated features.

If this computer shipped with Windows, the OEM key is still in firmware even after installing Omarchy. Print it with `omarchy windows key`. That key is bound to this machine — it will activate Windows reinstalled on this hardware, but it usually will not activate the VM.

You can change the resource allocation later by editing `~/.config/windows/docker-compose.yml`, which is also where you'd mount a USB device. See all the options on [the Dockur Windows project](https://github.com/dockur/windows).

To get rid of the whole thing, use _Remove > Windows_ from the Omarchy menu. That deletes the VM's disk and all its data, so make sure anything you care about is out of `~/Windows` first.
