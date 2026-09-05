# Lab VM

Omarchy can install a second, disposable Omarchy as a KVM guest on this machine. Use it when you want to break a desktop — a security PoC, a half-written shell, `omarchy dev link` against a checkout — without taking down the session you are sitting in.

Install it from _Install > Lab_ in the Omarchy menu (`Super + Space`), or run `omarchy lab vm install`.

Your machine needs KVM virtualization, which most do — but it's sometimes switched off in firmware, and the installer will tell you if that's the case. You'll also want the disk space: the Omarchy ISO is about 6GB, and the guest disk is sparse (80GB virtual by default).

The installer asks how much RAM, how many CPU cores, and how much disk to hand over, then for a guest username and password. CPU and RAM start at the Balanced workload of 4 cores and 8 GiB, capped downward when the host cannot safely provide it. Larger custom choices retain at least 25% for the desktop and other applications. Leave the credentials blank and you get `lab` / `lab`. It then downloads the current Omarchy ISO (or reuses one already in the libvirt image pool), attaches a `cidata` drive so the guest installs itself with nobody at the keyboard, waits for SSH, and freezes a gold image.

The guest is unencrypted on purpose. A lab that cannot reboot without a typed LUKS passphrase cannot be driven by an agent. Autologin and passwordless sudo are on the gold image for the same reason. Do not copy those conveniences to the host.

## Using it

Setup installs its virtualization dependencies and the SSH proxy tool automatically. On a fresh installation with missing package databases, it first runs the normal Omarchy update flow, including keyrings and migrations; this updates that machine and may require a reboot. Failed updates stop installation and are retried before dependencies are installed. The same recovery handles the new guest's display-agent package.

Installing Lab inside another VM requires nested KVM support. If the unused default libvirt network overlaps the outer VM's network, setup saves its original definition and chooses an unused private subnet. It refuses to renumber an active network or one already used by another VM.

Install and privileged workbench actions show an opening state and close the workbench once the terminal is ready, keeping authentication and progress visible. A failed terminal launch leaves the workbench open with an error and retry available.

Once it's installed, launch _Omarchy Lab_ from the app launcher. That starts the VM and opens its console through Omarchy's `virt-viewer` controller. Resize that window to change the guest resolution — Hyprland follows the SPICE framebuffer, so there is no resolution to pick in the installer.

While the console is open, a Lab icon appears in the Omarchy bar. Open it for the complete Lab workbench. Drag the workbench by its header to move it, use `Alt`+arrow keys for keyboard movement, or press `Alt`+`Home` to recenter it. Its position is retained when you close and reopen it during the shell session. The _Console_ page changes aspect ratio, zoom, automatic resizing, cursor rendering, audio, and USB redirection, and can toggle fullscreen, take a screenshot, reboot, stop, or reset the guest. Enable _Keep in bar_ there if you want the Lab icon to remain available as a launcher after closing the viewer. Reset requires a second confirmation because it permanently discards the current overlay. The same panel is available from _Trigger > Lab Controls_ in the Omarchy menu.

The aspect choices are 16:9, 16:10, 3:2, 4:3, 21:9, and 32:9. Omarchy accounts for the selected zoom while keeping the viewer as large as its current monitor allows. Viewer preferences persist between Lab sessions.

Select _Open Lab_ at the top of Console to start a stopped guest, reopen a closed viewer, or focus the existing console. The button shows _Opening Lab…_ while launching and the controls close after the launch request succeeds. If launching fails, the controls stay open so you can retry.

Reset and aspect changes restore missing display tools in guests made from older gold images and start the SPICE and resize services without requiring a reboot. This repairs only the active guest, leaving gold and checkpoints unchanged. The first repair needs internet access; if the guest has no package databases, it runs the normal full Omarchy update inside the guest before installing the tools.

The rest of the controls are on the same command:

```bash
omarchy lab vm status        # is it running, and what is its NAT lease?
omarchy lab vm launch        # start and attach the console
omarchy lab vm aspect 16:9   # resize the live display to a common aspect ratio
omarchy lab vm ssh           # SSH as the lab user
omarchy lab vm push ~/Work/omarchy
omarchy lab vm reset         # throw away the overlay and boot a fresh gold clone
omarchy lab vm stop
```

The graphical controls also have a scriptable interface:

```bash
omarchy lab viewer status
omarchy lab viewer aspect 16:10
omarchy lab viewer set zoom 125
omarchy lab viewer set auto-resize false
omarchy lab viewer set cursor local
omarchy lab viewer set audio false
omarchy lab viewer set usb-redirection false
omarchy lab viewer set keep-in-bar true
omarchy lab viewer fullscreen
```

`ssh omarchy-lab` works too: install writes a `Host omarchy-lab` block that looks up the current lease.

## The Lab workbench

Every workbench operation has both a graphical control and a scriptable `omarchy lab` command. Status and list commands accept `--json`, so agents can inspect the Lab without scraping human-readable output. Commands that discard data refuse to run non-interactively unless you pass `--yes`; the graphical panel requires a second click instead.

The _Develop_ page shows guest health, offers a searchable picker containing every local branch in your Omarchy repository, deploys or synchronizes the selected branch into the guest, and manages named disk checkpoints. A branch does not need its own checked-out worktree: Lab materializes its exact committed tree before copying it. Use the path-based command when you deliberately want to deploy dirty worktree changes. Creating a checkpoint stops the VM briefly so the qcow2 image is consistent. Checkpoints contain the guest disk but share the Lab's virtual TPM state.

```bash
omarchy lab health --json
omarchy lab checkout list --json
omarchy lab checkout branches --json
omarchy lab checkout deploy --branch feature/my-change --json
omarchy lab checkout deploy ~/Work/omarchy-feature --json
omarchy lab checkout sync --json
omarchy lab checkpoint create before-shell-change --json
omarchy lab checkpoint list --json
omarchy lab checkpoint restore before-shell-change --yes
omarchy lab checkpoint rename before-shell-change known-good
omarchy lab checkpoint delete known-good --yes
```

The _Environment_ page switches among normal NAT, a host-only isolated network, and a fully disconnected network interface. Isolated mode gives the guest the fixed address `192.168.123.2`, permits SSH from its host-only subnet, and deliberately gives it no default route. Resource profiles show the host capacity, current VM ceiling, and exact CPU/RAM allocation. Light is 2 cores/4 GiB, Balanced is the recommended 4/8 for most development and UI checks, Performance is 8/16 for heavier builds and multitasking, and Full is 16/32 for demanding workloads. These presets cap downward on smaller hosts instead of growing merely because a large host has more hardware. Custom fields can go higher while retaining at least 25% of host CPU and RAM for the desktop. The controller adjusts both the VM boot allocation and its configured resources to the selected profile, then power-cycles the guest to apply the change. Selecting a smaller profile also lowers the boot allocation so the guest does not retain excess memory from a previous profile. Gold-image promotion flattens the current overlay and retains one previous gold image; rebuilding reinstalls from the newest cached or current ISO. Both gold operations require confirmation.

```bash
omarchy lab network status --json
omarchy lab network isolated
omarchy lab network offline
omarchy lab network nat
omarchy lab resource status --json
omarchy lab resource set light       # up to 2 vCPU / 4 GiB
omarchy lab resource set balanced    # up to 4 vCPU / 8 GiB; recommended
omarchy lab resource set performance # up to 8 vCPU / 16 GiB
omarchy lab resource set full        # up to 16 vCPU / 32 GiB
omarchy lab resource set custom 6 12
omarchy lab gold status --json
omarchy lab gold promote --yes
omarchy lab gold rebuild --yes
```

The _Capture_ page saves framebuffer screenshots, real-time recordings of the Lab viewer, diagnostic bundles, and side-by-side comparisons. Recording closes the controls and focuses the viewer before starting. It captures a region of your desktop, so keep the viewer unobscured during recording. It also performs explicit clipboard and file transfers in either direction. There is no permanently shared host folder.

```bash
omarchy lab capture screenshot --copy --json
omarchy lab capture record 10 --copy --json
omarchy lab capture bundle --json
omarchy lab capture compare --copy --json
omarchy lab capture list --json
printf '%s' 'test text' | omarchy lab transfer clipboard-to
omarchy lab transfer clipboard-from --copy
omarchy lab transfer push ./fix.patch
omarchy lab transfer pull ~/Downloads/result.txt
```

The _Automate_ page exposes safe shortcuts for the graphical session and runs repeatable scenarios. Saved scenarios live in `~/.config/omarchy/lab-vm/scenarios/*.json`; every step is an argument array such as `{"command":["health","--json"]}`. The runner accepts only Lab command families and never evaluates shell strings.

```bash
omarchy lab action list --json
omarchy lab action launcher
omarchy lab action reload-hyprland
omarchy lab action key KEY_LEFTMETA KEY_ENTER
omarchy lab action run hyprctl clients -j
omarchy lab scenario list --json
omarchy lab scenario run smoke --json
omarchy lab scenario run visual-check --json
omarchy lab scenario run checkpoint-deploy feature/my-change --branch --json
omarchy lab scenario validate ~/.config/omarchy/lab-vm/scenarios/theme.json --json
```

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

Gold is a read-only qcow2. Every `reset` deletes the overlay and creates a new one backing gold, reconnecting it to the network saved with that image (NAT for the original installation). The TPM emulator state under `/var/lib/libvirt/swtpm/` is not wiped on reset. Checkpoints are self-contained disk images; existing dependent checkpoints are flattened before gold is promoted or rebuilt, so replacing gold does not change their contents. This may take time and additional disk space. Reset, promotion, and rebuild open a visible terminal when launched from the controls and request authentication before destructive work begins; promotion reuses that terminal's sudo authentication instead of opening a separate password dialog for each disk operation.

Changing between NAT and isolated networking requires a running guest so Lab can prepare its network profile before switching. If the guest is offline, Lab first reconnects its current network. Start a stopped guest and select NAT or isolated again; source changes are rejected while it is stopped.

To get rid of the whole thing, use _Remove > Lab_ from the Omarchy menu. That deletes the VM and its disks. The hypervisor packages, UFW rules, and downloaded ISO stay, so a later install is faster.

See also [Unattended Installs](51-unattended-installs.md) for the `cidata` mechanism the lab uses.
