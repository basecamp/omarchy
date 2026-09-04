# Lab VM

Omarchy can install a second, disposable Omarchy as a KVM guest on this machine. Use it when you want to break a desktop — a security PoC, a half-written shell, `omarchy dev link` against a checkout — without taking down the session you are sitting in.

Install it from _Install > Lab_ in the Omarchy menu (`Super + Space`), or run `omarchy lab vm install`.

Your machine needs KVM virtualization, which most do — but it's sometimes switched off in firmware, and the installer will tell you if that's the case. You'll also want the disk space: the Omarchy ISO is about 6GB, and the guest disk is sparse (80GB virtual by default).

The installer asks how much RAM, how many CPU cores, and how much disk to hand over, then for a guest username and password. Leave those blank and you get `lab` / `lab`. It then downloads the current Omarchy ISO (or reuses one already in the libvirt image pool), attaches a `cidata` drive so the guest installs itself with nobody at the keyboard, waits for SSH, and freezes a gold image.

The guest is unencrypted on purpose. A lab that cannot reboot without a typed LUKS passphrase cannot be driven by an agent. Autologin and passwordless sudo are on the gold image for the same reason. Do not copy those conveniences to the host.

## Using it

Once it's installed, launch _Omarchy Lab_ from the app launcher. That starts the VM if it isn't already running and attaches `virt-viewer`.

The rest of the controls are on the same command:

```bash
omarchy lab vm status        # is it running, and what is its NAT lease?
omarchy lab vm launch        # start and attach the console
omarchy lab vm ssh           # SSH as the lab user
omarchy lab vm push ~/Work/omarchy
omarchy lab vm reset         # throw away the overlay and boot a fresh gold clone
omarchy lab vm stop
```

`ssh omarchy-lab` works too: install writes a `Host omarchy-lab` block that looks up the current lease.

## Developing inside the guest

The host keeps the editor and the agent. Copy a checkout in and link it in the guest:

```bash
omarchy lab vm push ~/Work/omarchy
omarchy lab vm ssh
# inside the guest:
omarchy dev link
```

After a reboot, `omarchy version` in the guest reports `dev`. `omarchy lab vm reset` restores the packaged gold image — no checkout, no greeter.

`omarchy lab vm session cmd` runs a command with the Hyprland session environment already set, which is what you want for screenshot and menu PoCs. `omarchy lab vm screenshot` captures the virtio display from the host, which is more reliable than asking the guest to screenshot itself. `omarchy lab vm send-key KEY_LEFTMETA KEY_ENTER` types into the guest when you cannot SSH.

## Isolation

`qemu:///system` runs QEMU as `libvirt-qemu`. The ISO and disks live in `/var/lib/libvirt/images/`, not under `$HOME`. A `700` home directory is correct; the lab does not punch a search ACL through it.

The guest is on libvirt's `default` NAT (`virbr0`, `192.168.122.0/24`). Host UFW stays default-deny. The installer opens only DHCP (UDP 67 to any, because a discover is broadcast to `255.255.255.255`), DNS to `192.168.122.1`, and FORWARD from `virbr0` out the uplink. It does not `ufw allow in on virbr0` with no port — that would let the guest hit every host service bound on `0.0.0.0`.

Gold is a read-only qcow2. Every `reset` deletes the overlay and creates a new one backing gold. The TPM emulator state under `/var/lib/libvirt/swtpm/` is not wiped on reset.

To get rid of the whole thing, use _Remove > Lab_ from the Omarchy menu. That deletes the VM and its disks. The hypervisor packages, UFW rules, and downloaded ISO stay, so a later install is faster.

See also [Unattended Installs](51-unattended-installs.md) for the `cidata` mechanism the lab uses.
