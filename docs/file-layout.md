# File layout

How `omarchy/` is organized and where everything ends up on an installed
system.

## Mental model

Four Arch packages are built from this one repo (PKGBUILDs live in
`omarchy-pkgs/pkgbuilds/`):

- **`omarchy`** — runtime binaries (`bin/`), install/finalize scripts
  (`install/`), migrations, themes, and the Quickshell desktop (`shell/`).
- **`omarchy-settings`** — user defaults (seeded via `/etc/skel`), `/etc/`
  drop-ins, package-owned system files under `/usr/share` and `/usr/lib`,
  fonts, plymouth theme, sddm theme, branding. Carves out `default/limine/`
  and `default/snapper/` (owned by `omarchy-limine`).
- **`omarchy-dev-tools`** — just `bin/omarchy-dev-*`. Optional dep of
  `omarchy`; installed for contributors, not end users.
- **`omarchy-limine`** — `default/limine/` and `default/snapper/` from this
  repo, plus mkinitcpio and limine-entry-tool drop-ins that live alongside
  the PKGBUILD in `omarchy-pkgs/`. Owns the boot/snapshot story end-to-end.

Three layers populate `$HOME`:

1. **Seed** — `omarchy-settings` ships static defaults to `/etc/skel/`.
   Arch's `useradd -m` copies that tree into a new user's `$HOME` at user
   creation. This is the only mechanism that touches a brand-new user's home
   for these files.
2. **Finalize** — `omarchy-finalize-user` runs once per user and handles the
   things `/etc/skel` can't do because they need `$HOME` expansion, the live
   `$OMARCHY_PATH`, or runtime detection of system state.
3. **Resync** — `omarchy-reinstall-configs` is the explicit, destructive
   command for an existing user to clobber their configs back to shipped
   defaults.

`/etc/skel` only fires at user creation. Existing users picking up new
defaults must use the resync command.

## Build-time map (repo → installed paths)

```
omarchy/                            built into          installed at
─────────────────────────           ──────────────      ────────────────────────────────────

bin/omarchy-*                  ──►  omarchy             /usr/bin/omarchy-*
                                                        (and symlinks in /usr/share/omarchy/bin/)
bin/omarchy-dev-*              ──►  omarchy-dev-tools   /usr/bin/omarchy-dev-*
bin/omarchy-debug,
bin/omarchy-debug-idle,
bin/omarchy-upload-log         ──►  omarchy-settings    /usr/bin/  (needed before omarchy is installed)

install/**                     ──►  omarchy             /usr/share/omarchy/install/
migrations/**                  ──►  omarchy             /usr/share/omarchy/migrations/
themes/**                      ──►  omarchy             /usr/share/omarchy/themes/
shell/**                       ──►  omarchy             /usr/share/omarchy/shell/
version                        ──►  omarchy             /usr/share/omarchy/version
                                                        + /etc/skel/.local/state/omarchy/migrations/*

config/**                      ──►  omarchy-settings    /etc/skel/.config/**         (seeds new users)
                                                        /usr/share/omarchy/config/** (resync source)

applications/*.desktop         ──►  omarchy-settings    /etc/skel/.local/share/applications/
                                                        /usr/share/omarchy/applications/
applications/icons/*           ──►  omarchy-settings    /usr/share/icons/hicolor/{48,256,scalable}/apps/

etc/**                         ──►  omarchy-settings    /etc/**           (drop-ins we own outright)

default/limine/limine.conf     ──►  omarchy-limine      /usr/share/omarchy/default/limine/limine.conf
default/limine/default.conf    ──►  omarchy-limine      /usr/share/omarchy/default/limine/default.conf
                                                        (template; ISO substitutes @@CMDLINE@@ → /etc/default/limine)
default/snapper/root           ──►  omarchy-limine      /etc/snapper/config-templates/omarchy

default/**                     ──►  omarchy-settings    /usr/share/omarchy/default/  (excluding default/{limine,snapper})
  ├─ bashrc                                             /usr/share/omarchy/etc-overrides/dot.bashrc
  │                                                       → /etc/skel/.bashrc (post_install cp -f)
  ├─ hypr/toggles/flags.lua                             /etc/skel/.local/state/omarchy/toggles/hypr/
  ├─ nautilus-python/extensions/*.py                    /etc/skel/.local/share/nautilus-python/extensions/
  ├─ uwsm/env.d/10-omarchy                              /usr/share/uwsm/env.d/
  ├─ environment.d/*.conf                               /usr/lib/environment.d/
  ├─ fontconfig/conf.avail/30-omarchy.conf              /usr/share/fontconfig/conf.avail/
  │                                                       + symlink /etc/fonts/conf.d/30-omarchy.conf
  ├─ xdg-terminal-exec/*.list                           /usr/share/xdg-terminal-exec/
  ├─ applications/mimeapps.list                         /usr/share/applications/mimeapps.list
  ├─ systemd/user/*.service                             /usr/lib/systemd/user/
  ├─ systemd/system-sleep/unmount-fuse                  /usr/lib/systemd/system-sleep/
  ├─ fonts/omarchy/omarchy.ttf                          /usr/share/fonts/omarchy/
  ├─ sddm/omarchy/                                      /usr/share/sddm/themes/omarchy/
  ├─ sddm/hyprland.lua                                  /usr/share/sddm/hyprland.lua
  ├─ wayland-sessions/omarchy.desktop                   /usr/local/share/wayland-sessions/
  ├─ plymouth/                                          /usr/share/plymouth/themes/omarchy/
  └─ security/faillock, nsswitch, cups-browsed,
     plymouthd.conf, os-release                         /usr/share/omarchy/etc-overrides/
                                                          → /etc/* (post_install cp -f, see below)

logo.{txt,svg}, icon.{txt,png}  ──► omarchy-settings    /usr/share/omarchy/  (resync source)
                                                        /usr/share/pixmaps/omarchy.png
                                                        /usr/share/icons/hicolor/256x256/apps/omarchy.png
                                                        /etc/skel/.config/omarchy/branding/{about,screensaver}.txt
```

### Why `etc-overrides/` exists

Some files under `/etc/` (`.bashrc` in `/etc/skel`, `nsswitch.conf`,
`security/faillock.conf`, `cups/cups-browsed.conf`, `plymouth/plymouthd.conf`,
`os-release`) are owned by upstream Arch packages, so we can't install over
them via pacman without a file conflict. Instead they ship at
`/usr/share/omarchy/etc-overrides/` and the `omarchy-settings` `post_install`
/ `post_upgrade` scriptlet `cp -f`'s them into place.

Tradeoff: user edits to those files get clobbered on every `omarchy-settings`
upgrade. This is documented in the PKGBUILD.

## Runtime finalization (`omarchy-finalize-user`)

Runs once per user. It does **not** copy `~/.config/**`, `~/.bashrc`,
`flags.lua`, or the nautilus extensions — `/etc/skel` already seeded those.
It only does the things `/etc/skel` can't:

- Skill symlinks `~/.{agents,claude,codex,pi/agent}/skills/omarchy` →
  `$OMARCHY_PATH/default/omarchy-skill`. Symlinks (not copies) so
  `omarchy dev link` against a dev checkout repoints them correctly.
- `xdg-user-dirs-update` (Templates/Public/Desktop folded back into `$HOME`)
  and `~/.config/gtk-3.0/bookmarks` (needs `$HOME` expansion).
- Sync `XKBLAYOUT` / `XKBVARIANT` from `/etc/vconsole.conf` into
  `~/.config/hypr/input.lua`.
- `xdg-settings set default-web-browser chromium.desktop` and
  `xdg-mime default HEY.desktop x-scheme-handler/mailto` (XDG-aware paths).
- `omarchy-refresh-applications` (composes generated `.desktop` launchers).
- Sources `install/user/all.sh` — theme, git, mise, keyring, per-user
  hardware quirks (bluetooth, asus mic/mixer, framework f13 audio, …).
- On `--first-install`, marks every shipped migration as already applied
  for the freshly-created user.

Idempotency marker: `~/.local/state/omarchy/finalize-user.done`.

The ISO calls it as `omarchy-finalize-user --force --first-install` in the
target chroot as the install user, after `omarchy-setup-system` has finished
the root-side work.

## Root-side install orchestration

`omarchy-setup-system` (root, in chroot) runs target-side setup at ISO
finalization. It sources:

- `install/config/*.sh` — theme links, lockout limits, lockscreen PAM,
  powerprofilesctl shebang fix, docker setup, service enablement, firewall.
- `install/hardware/all.sh` via `omarchy-setup-hardware` — vendor- and
  device-specific kernel modules, udev rules, microcode, wireless regdom,
  ASUS / Framework / Intel / Apple / Lenovo quirks.
- `install/login/*.sh` — SDDM theme/session config.
- `install/post-install/*.sh` — final pacman/udev/localdb passes.

Logging goes to `/var/log/omarchy-install.log` via
`install/helpers/logging.sh`.

## Explicit resync (`omarchy-reinstall-configs`)

When an existing user wants to reset to shipped defaults:

```
~/  ←  cp -af /etc/skel/.
```

Replaying `/etc/skel` over `$HOME` is exactly what `useradd -m` does for a
brand-new user, so this one copy resyncs `.bashrc`, `.config/**`,
`.local/share/applications/`, the nautilus-python extensions, hypr toggles,
branding files, and the shipped migration markers in a single pass.

Then it runs `omarchy-refresh-limine`, `omarchy-refresh-plymouth`, and the
nvim refresh. Destructive: existing user files at these paths are clobbered
without backup.

## Quick reference: where does X live?

| Goal | Touch |
| --- | --- |
| Default file at `~/.config/foo/` | `config/foo/` |
| `/etc/` drop-in we own outright | `etc/` |
| `/etc/` file owned by an upstream package | `default/`, then add to `etc-overrides` in `omarchy-settings` PKGBUILD + scriptlet |
| Package-owned system file (e.g. systemd user service in `/usr/lib`) | `default/`, document the mapping in `default/package-defaults.tsv`, then add the `install -Dm644` line in `omarchy-settings` PKGBUILD |
| Per-user file that's static but lives outside `~/.config` | `default/`, then add `install -Dm644 ... $pkgdir/etc/skel/...` in `omarchy-settings` PKGBUILD |
| Runtime tweak that needs `$HOME` or live system state | extend `omarchy-finalize-user`, or add a per-user leaf under `install/user/` and wire into `install/user/all.sh` |
| One-time root-side setup step | `install/config/*.sh` or `install/hardware/*.sh`, wire into `omarchy-setup-system` or `install/hardware/all.sh` |
| User-facing `omarchy-*` command | `bin/omarchy-<group>-<verb>` — see `GROUP_DESCRIPTIONS` in `bin/omarchy` |
| New theme | `themes/<name>/` (+ matching templates under `default/themed/` if they need theme colors) |
| One-shot fix for installed systems | `migrations/<unix-timestamp>.sh` (use `omarchy-dev-add-migration --no-edit`) |
