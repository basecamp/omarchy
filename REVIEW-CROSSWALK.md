# Installer Revamp Review Crosswalk

This branch is easiest to review as a behavior migration: each row below maps an old install script/behavior to its new owner and phase.

## Install architecture

| Phase | Entry point | Runs as | Runs when | Owns |
|---|---|---|---|---|
| System install | `system-finalize.sh` -> `install/system/all.sh` | root | once at install/finalize time | machine config, services, login manager, root-owned post-install cleanup |
| User setup | `omarchy-setup-user` -> `install/user/all.sh` | target user | install user during `finalize.sh`, and every future user on first login | home config, AI skills, XDG dirs, app launchers, user services, user/session hardware tweaks |
| User finalization | `finalize.sh` | target user | once during install | marks shipped migrations done, creates offline first-run marker, calls `omarchy-setup-user --force`, shows finish/reboot UI |
| First run system one-shot | `omarchy-first-run` when `~/.local/state/omarchy/first-run.mode` exists | install user with temporary sudoers | first graphical login after offline install | firewall/DNS/icon-cache/voxtype work that needs a live boot |
| First run user one-shot | `omarchy-first-run` when `first-run-user.done` is missing | current user | first graphical login for every user | session-only user tasks: monitor recovery, GNOME settings, primary paste, welcome, Wi-Fi |
| Package-owned defaults | `etc/**`, `config/**`, `applications/**`, `default/**` via `omarchy-settings` / `omarchy` packages | pacman | package install/upgrade | static `/etc`, `/etc/skel`, `/usr/share/omarchy` defaults |

Rules of thumb:

- `install/system/**` should not write a user's home directory except through explicit target-user metadata like `OMARCHY_INSTALL_USER`.
- `omarchy-setup-user` is the canonical path for current and future users. `/etc/skel` seeds new homes, but setup-user keeps existing users and first-login users aligned.
- `install/user/**` contains reusable user setup pieces, but callers should normally invoke `omarchy-setup-user` rather than source those files directly.

## Crosswalk

| Old file / behavior | New owner(s) | Phase | Review status / verification |
|---|---|---|---|
| `install.sh` ran package install then directly entered `finalize.sh`. | `install.sh` now runs root `system-finalize.sh`, then user `finalize.sh`. | system -> user | `rg 'system-finalize|finalize.sh' install.sh` |
| `finalize.sh` ran all system/user/post-install phases. | `system-finalize.sh` owns system phases; `finalize.sh` now calls `omarchy-setup-user --force` and `post-install/finished.sh`. | split | `rg 'omarchy-setup-user|finished.sh|system/all' finalize.sh system-finalize.sh` |
| `install/packaging/all.sh` mixed hardware package work and user app setup. | `install/packaging/system.sh` for hardware-gated packages; `install/packaging/user.sh` for user package setup (`nvim`). App launchers/npm wrappers are driven through `omarchy-refresh-applications` in setup-user. | split | `cat install/packaging/{all,system,user}.sh` |
| `install/config/config.sh` copied `config/**` and bashrc into the install user's home. | `omarchy-settings` seeds `/etc/skel`; `omarchy-setup-user` copies `config/**`, `.bashrc`, and `.bash_profile` for existing/current users. | user setup + package/skel | `rg 'cp -R .*config|bashrc' bin/omarchy-setup-user` |
| `install/config/theme.sh` mixed system icon/Chromium setup and user theme setup. | `install/config/theme-system.sh` and `install/config/theme-user.sh`. | split | `cat install/config/theme-{system,user}.sh` |
| `install/first-run/gnome-theme.sh` mixed user `gsettings` with root icon-cache refresh. | `install/first-run/gnome-theme-system.sh` and `install/first-run/gnome-theme-user.sh`. | first-run split | `cat install/first-run/gnome-theme-{system,user}.sh` |
| `install/config/branding.sh` copied branding into the user config. | `/etc/skel/.config/omarchy/branding` via package plus refresh in `omarchy-setup-user`. | package + user setup | `rg 'branding' bin/omarchy-setup-user /home/ryan/Work/omarchy/omarchy-pkgs/pkgbuilds/omarchy-settings/PKGBUILD` |
| `install/config/omarchy-ai-skill.sh` symlinked assistant skills. | `omarchy-setup-user`. | per-user | `rg 'skills/omarchy' bin/omarchy-setup-user` |
| `install/config/omarchy-toggles.sh` seeded toggle flags. | `omarchy-setup-user`; `omarchy-refresh-hyprland` also refreshes flags when resetting Hypr configs. | per-user | `rg 'flags.lua|toggles' bin/omarchy-setup-user bin/omarchy-refresh-hyprland` |
| `install/config/detect-keyboard-layout.sh` inserted `/etc/vconsole.conf` layout into Hypr config. | `omarchy-setup-user`; `omarchy-refresh-hyprland` contains the same idempotent refresh behavior. | per-user | `rg 'XKBLAYOUT|kb_layout' bin/omarchy-setup-user bin/omarchy-refresh-hyprland` |
| `install/config/user-dirs.sh` created XDG dirs/bookmarks. | `omarchy-setup-user` with idempotent bookmark insertion. | per-user | `rg 'xdg-user-dirs|bookmarks' bin/omarchy-setup-user` |
| `install/config/mimetypes.sh` set app/MIME defaults. | `omarchy-refresh-applications` plus `xdg-settings` / `xdg-mime` in `omarchy-setup-user`. | per-user | `rg 'omarchy-refresh-applications|xdg-mime|xdg-settings' bin/omarchy-setup-user` |
| `install/config/nautilus-python.sh` copied Nautilus extensions. | `omarchy-setup-user`. | per-user | `rg 'nautilus-python' bin/omarchy-setup-user` |
| `install/config/localdb.sh` ran `updatedb`. | `install/post-install/localdb.sh`. | system post-install | `cat install/post-install/localdb.sh` |
| `install/config/docker.sh` restarted/daemon-reloaded Docker bits and added current user to docker. | Package-owned Docker/resolved config in `etc/**`; `docker.sh` keeps the install-user group membership. | system + package | `cat install/config/docker.sh etc/docker/daemon.json etc/systemd/system/docker.service.d/no-block-boot.conf` |
| `install/config/enable-services.sh` and service enables scattered elsewhere. | `install/config/enable-services.sh` is the centralized service-enable step for bluetooth/cups/avahi/docker/NetworkManager/power-profiles/sddm. | system | `rg 'systemctl enable' install` |
| `install/config/hardware/network.sh` enabled NetworkManager and disabled iwd/wait-online. | NetworkManager enable moved to `enable-services.sh`; `network.sh` only disables iwd and masks wait-online. | system | `cat install/config/enable-services.sh install/config/hardware/network.sh` |
| `install/config/hardware/bluetooth.sh` mixed `/etc/bluetooth` with user WirePlumber and `bt-agent`. | `bluetooth.sh` keeps system AutoEnable; `bluetooth-user.sh` handles user WirePlumber and user service; `/etc/skel` symlink seeds future users. | split | `cat install/config/hardware/bluetooth{,-user}.sh; find config/systemd/user -maxdepth 3 -type l -ls` |
| `install/config/hardware/nvidia.sh` installed drivers, wrote `/etc`, and appended user Hypr env vars. | `nvidia.sh` keeps driver/system config; `nvidia-user.sh` appends user env vars idempotently. | split | `cat install/config/hardware/nvidia{,-user}.sh` |
| ASUS audio mixer/mic scripts ran in system config. | Moved to `install/config/user.sh`; behavior preserved in `asus/fix-audio-mixer.sh` and `asus/fix-mic.sh`. | per-user/session | `rg 'fix-audio-mixer|fix-mic' install/config/user.sh install/config/hardware/asus` |
| Framework AMD F13 audio input ran in system config. | Moved to `install/config/user.sh`; `framework/fix-f13-amd-audio-input.sh` preserves the `pactl` profile fix. | per-user/session | `rg 'fix-f13|pactl' install/config/user.sh install/config/hardware/framework` |
| `install/config/hardware/fix-synaptic-touchpad.sh` was removed in the split. | Restored and called from `install/config/all.sh`. | system hardware | `rg 'fix-synaptic-touchpad' install/config/all.sh install/config/hardware/fix-synaptic-touchpad.sh` |
| `install/config/lockscreen-pam.sh` delegated to `omarchy-setup-lock`. | Kept as `omarchy-setup-lock`; `omarchy-setup-lock` now honors `OMARCHY_INSTALL_USER`. | system helper | `cat install/config/lockscreen-pam.sh; rg 'OMARCHY_INSTALL_USER' bin/omarchy-setup-lock` |
| `install/config/increase-fd-limit.sh` wrote systemd manager nofile drop-ins. | Package-owned `etc/systemd/system.conf.d/20-omarchy-nofile.conf` and `etc/systemd/user.conf.d/20-omarchy-nofile.conf`; legacy `99` files removed by `post-install/legacy-cleanup.sh`. | package + cleanup | `cat etc/systemd/{system.conf.d,user.conf.d}/20-omarchy-nofile.conf install/post-install/legacy-cleanup.sh` |
| `install/config/increase-file-watchers.sh` ran `sysctl --system`. | Package-owned `etc/sysctl.d/90-omarchy-file-watchers.conf`; install is followed by reboot. | package | `cat etc/sysctl.d/90-omarchy-file-watchers.conf` |
| `install/config/fast-shutdown.sh` only reloaded systemd after drop-ins. | Package-owned faster-shutdown drop-ins; install is followed by reboot. | package | `cat etc/systemd/system.conf.d/10-faster-shutdown.conf etc/systemd/system/user@.service.d/10-faster-shutdown.conf` |
| `install/config/powerprofilesctl-rules.sh` and `wifi-powersave-rules.sh` wrote/reloaded udev rules. | Package-owned `etc/udev/rules.d/99-omarchy-*.rules`; `post-install/legacy-cleanup.sh` removes old non-namespaced rules; `post-install/udev.sh` reloads/triggers. | package + post-install | `cat etc/udev/rules.d/99-omarchy-*.rules install/post-install/{legacy-cleanup,udev}.sh` |
| `install/config/gpg.sh` copied GnuPG config and restarted dirmngr. | Package-owned `etc/gnupg/dirmngr.conf`; live dirmngr restart removed. | package | `cat etc/gnupg/dirmngr.conf` |
| `install/config/pi.sh` activated Pi theme. | No direct install path remains; theme changes still run Pi retint hooks when applicable. | intentionally removed / review | `rg 'omarchy-theme-set-pi' bin install migrations` |
| `install/login/all.sh` mixed default keyring with SDDM/login manager work. | `install/login/system.sh` owns SDDM/hibernation/limine; `install/login/default-keyring.sh` runs through user setup and is idempotent. | split | `cat install/login/system.sh install/login/default-keyring.sh` |
| `install/login/sddm.sh` wrote static SDDM config, autologin, PAM tweaks, and enabled service. | Static `10-wayland.conf` and `10-theme.conf` live under `etc/sddm.conf.d`; `sddm.sh` manages autologin and remaining live file copies/PAM tweaks; service enable moved to `enable-services.sh`. | package + system | `cat etc/sddm.conf.d/*.conf install/login/sddm.sh install/config/enable-services.sh` |
| `install/post-install/allow-reboot.sh` created online reboot sudoers. | Kept, now also grants one-time cleanup; `omarchy-first-run` calls `cleanup-reboot-sudoers.sh` with `sudo -n` so future users are not prompted. | online post-install + first-run cleanup | `cat install/post-install/allow-reboot.sh install/first-run/cleanup-reboot-sudoers.sh` |

## Deleted migration/helper policy

Old migrations that only sourced helpers now replaced by package-owned files were removed with their helpers. Legacy cleanup that still matters moved into `install/post-install/legacy-cleanup.sh`:

- old udev rule names: `/etc/udev/rules.d/99-power-profile.rules`, `/etc/udev/rules.d/99-wifi-powersave.rules`
- old nofile drop-in names: `/etc/systemd/system.conf.d/99-omarchy-nofile.conf`, `/etc/systemd/user.conf.d/99-omarchy-nofile.conf`

## Review commit plan

The branch should be reviewed in this order:

1. `installer: split root and user finalization`
   - `install.sh`, `system-finalize.sh`, `finalize.sh`, `install/system/all.sh`, `install/user/all.sh`, helper/root-aware changes.
2. `setup: make omarchy-setup-user canonical for users`
   - `bin/omarchy-setup-user`, `bin/omarchy-first-run`, user setup idempotency fixes, `default-keyring`, `cleanup-reboot-sudoers`.
3. `install: split packaging phases`
   - `install/packaging/{all,system,user}.sh` and app setup routing through `omarchy-refresh-applications`.
4. `install: split theme and first-run theme setup`
   - `theme.sh` -> `theme-system.sh` / `theme-user.sh`; `gnome-theme.sh` -> first-run system/user split.
5. `install: move static system config to package-owned files`
   - `etc/**` additions, removal of no-op helpers/migrations, post-install legacy cleanup/udev/localdb.
6. `install: split user-scoped hardware/session config`
   - bluetooth/nvidia split, ASUS/Framework user audio fixes, Synaptics restoration.
7. `install: split SDDM config from autologin`
   - package-owned SDDM drop-ins, trimmed `sddm.sh`, centralized service enable.
8. `docs: add installer review crosswalk`
   - this file.

## Follow-up checks

```bash
git status --porcelain=v1 --untracked-files=all
rg 'systemctl enable' install
rg 'fast-shutdown|increase-file-watchers|powerprofilesctl-rules|wifi-powersave-rules|increase-fd-limit' install migrations bin || true
bash -n install.sh system-finalize.sh finalize.sh bin/omarchy-setup-user bin/omarchy-first-run
bash test/offline-finalizer-bootstrap-test.sh
```
