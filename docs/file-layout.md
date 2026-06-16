# File layout

How `omarchy/` is organized and where everything ends up on an installed
system.

## Mental model

Two Arch packages are built from this one repo (PKGBUILDs live in
`omarchy-pkgs/pkgbuilds/`):

- **`omarchy`** — runtime binaries (`bin/`, including `bin/omarchy-dev-*`),
  install/finalize scripts (`install/`), migrations, themes, and the
  Quickshell desktop (`shell/`). Depends on `omarchy-settings`.
- **`omarchy-settings`** — everything that has to be on the target *before*
  the omarchy package installs (specifically before `useradd -m` and the
  limine bootloader install): all `/etc/skel/**`, `/etc/` drop-ins,
  package-owned system files under `/usr/share` and `/usr/lib`, fonts,
  plymouth theme, sddm theme, branding, plus the limine/snapper configs
  (mkinitcpio hooks, limine-entry-tool drop-ins, snapper template, the
  `default/limine/` and `default/snapper/` trees, and the boot/snapshot
  story end-to-end). Also ships the three debug binaries
  (`omarchy-debug`, `omarchy-debug-idle`, `omarchy-upload-log`) needed by
  the live ISO env.

Two other packages live in `omarchy-pkgs/` but stand alone:
`omarchy-keyring` (GPG keys for pacman) and `omarchy-nvim` (the Neovim
setup; independently seeds `/etc/skel`).

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

Current generated theme state lives under
`~/.local/state/omarchy/current/`. Keep `~/.config/omarchy/` for files a user
may intentionally version in a dotfile manager, such as user themes, hooks,
shell layout, plugin sources, and themed template overrides.

## Build-time map (repo → installed paths)

```
omarchy/                            built into          installed at
─────────────────────────           ──────────────      ────────────────────────────────────

bin/omarchy-*                  ──►  omarchy             /usr/bin/omarchy-*
                                                        (and symlinks in /usr/share/omarchy/bin/)
bin/omarchy-debug,
bin/omarchy-debug-idle,
bin/omarchy-upload-log         ──►  omarchy-settings    /usr/bin/  (needed before omarchy is installed)

default/libalpm/hooks/*.hook
                                ──►  omarchy             /usr/share/libalpm/hooks/*.hook

install/**                     ──►  omarchy             /usr/share/omarchy/install/
migrations/**                  ──►  omarchy             /usr/share/omarchy/migrations/
themes/**                      ──►  omarchy             /usr/share/omarchy/themes/
shell/**                       ──►  omarchy             /usr/share/omarchy/shell/
version                        ──►  omarchy             /usr/share/omarchy/version
                                                        + /etc/skel/.local/state/omarchy/migrations/*

config/**                      ──►  omarchy-settings    /etc/skel/.config/**         (seeds new users)
                                                        /usr/share/omarchy/config/** (resync source)
etc/fastfetch/config.jsonc     ──►  omarchy-settings    /etc/fastfetch/config.jsonc

applications/*.desktop         ──►  omarchy-settings    /etc/skel/.local/share/applications/
                                                        /usr/share/omarchy/applications/
applications/icons/*           ──►  omarchy-settings    /usr/share/icons/hicolor/{48,256,scalable}/apps/

etc/**                         ──►  omarchy-settings    /etc/**           (drop-ins we own outright)
  ├─ mkinitcpio.conf.d/{omarchy_hooks,thunderbolt_module}.conf
  └─ limine-entry-tool.d/{omarchy-defaults,omarchy-uki}.conf

default/limine/limine.conf     ──►  omarchy-settings    /usr/share/omarchy/default/limine/limine.conf
default/limine/default.conf    ──►  omarchy-settings    /usr/share/omarchy/default/limine/default.conf
                                                        (template; ISO substitutes @@CMDLINE@@ → /etc/default/limine)
default/snapper/root           ──►  omarchy-settings    /etc/snapper/config-templates/omarchy
                                                        (+ /usr/share/omarchy/default/snapper/root)

default/**                     ──►  omarchy-settings    /usr/share/omarchy/default/
  ├─ bash/env-bootstrap                                 /usr/share/omarchy/default/bash/env-bootstrap
  │                                                       (sourced by every shell/session entry point; see "Env bootstrap")
  ├─ bashrc                                             /usr/share/omarchy/etc-overrides/dot.bashrc
  │                                                       → /etc/skel/.bashrc (post_install cp -f)
  ├─ hypr/toggles/flags.lua                             /etc/skel/.local/state/omarchy/toggles/hypr/
  ├─ nautilus-python/extensions/*.py                    /etc/skel/.local/share/nautilus-python/extensions/
  ├─ uwsm/env.d/10-omarchy                              /usr/share/uwsm/env.d/
  ├─ environment.d/*.conf                               /usr/lib/environment.d/
  ├─ fontconfig/conf.avail/50-omarchy.conf              /usr/share/fontconfig/conf.avail/
  │                                                       + symlink /etc/fonts/conf.d/50-omarchy.conf
  ├─ xdg-terminal-exec/*.list                           /usr/share/xdg-terminal-exec/
  ├─ applications/mimeapps.list                         /usr/share/applications/mimeapps.list
  ├─ systemd/user/*.{service,path}                      /usr/lib/systemd/user/
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

## Env bootstrap (`default/bash/env-bootstrap`)

Single source of truth for `OMARCHY_PATH` and dev-link-aware `PATH`. It:

- Sources `/etc/omarchy.conf` (written by `omarchy-dev-link`, reset to the
  package path by `omarchy-dev-unlink`) if present; otherwise forces
  `OMARCHY_PATH=/usr/share/omarchy` so a stale inherited value can't survive
  an `omarchy-dev-unlink`.
- Prepends `$OMARCHY_PATH/bin` to `PATH` **only when** `OMARCHY_PATH` is
  not `/usr/share/omarchy`. On a production install the binaries are
  already on `PATH` as `/usr/bin/omarchy-*` via the `omarchy` package.

Sourced by every entry point that needs the env set:

```
/etc/profile.d/omarchy.sh                      (system login shells)
/etc/skel/.bashrc                              (interactive shells)
/usr/share/uwsm/env.d/10-omarchy               (Hyprland session via uwsm)
/usr/share/omarchy/default/bash/envs           (SSH / non-login bash)
```

Idempotent — safe to source more than once in the same shell.

## Runtime finalization (`omarchy-finalize-user`)

Runs once per user. It does **not** copy `~/.config/**`, `~/.bashrc`,
`flags.lua`, or the nautilus extensions — `/etc/skel` already seeded those.
It only does the things `/etc/skel` can't:

- Skill symlinks `~/.{agents,claude,codex,pi/agent}/skills/omarchy` →
  `$OMARCHY_PATH/default/omarchy-skill`. Symlinks (not copies) so
  `omarchy dev link` against a dev checkout repoints them correctly.
- `xdg-user-dirs-update` (Templates/Public/Desktop folded back into `$HOME`)
  and `~/.config/gtk-3.0/bookmarks` (needs `$HOME` expansion).
- Hyprland's package-owned default input reads `XKBLAYOUT` / `XKBVARIANT`
  from `/etc/vconsole.conf`; no per-user Hyprland config rewrite is needed.
- `xdg-settings set default-web-browser chromium.desktop` and
  `xdg-mime default HEY.desktop x-scheme-handler/mailto` (XDG-aware paths).
- `omarchy-refresh-applications` (composes generated `.desktop` launchers).
- Sources `install/user/all.sh` — theme, git, mise, keyring, per-user
  hardware quirks (asus mic/mixer, framework f13 audio, …).
- On `--first-install`, marks every shipped user migration as already applied
  for the freshly-created user.

Idempotency marker: `~/.local/state/omarchy/finalize-user.done`.

The ISO calls it as `omarchy-finalize-user --force --first-install` in the
target chroot as the install user, after `omarchy-setup-system` has finished
the root-side work.

## Migrations (`omarchy-migrate`)

See [`migrations.md`](migrations.md) for the full migration model, authoring
guidelines, and troubleshooting notes.

Omarchy migrations live in `migrations/*.sh` and run per-user through
`omarchy-migrate`. Completion state lives in
`~/.local/state/omarchy/migrations/`, so every user gets a chance to run every
migration. Migrations run as the user; privileged work should invoke the
appropriate helper or privilege prompt. Migrations must be idempotent;
machine-wide repairs should no-op when another user already applied them.

Each graphical user has `omarchy-update-user-notify.path` watching the packaged
migration directory. When that directory changes, or when the path unit is
started on login, `omarchy-update-user-notify.service` runs
`omarchy-migrate-notify` as that user. The notifier checks
`omarchy-migrate --pending`. If this user has missing migration state, it shows a
notification that opens a terminal for `omarchy-migrate`. The notifier never runs
migrations in the background.

`omarchy-migrate` waits for any active pacman transaction to finish, then runs
pending migrations. It does not need `--force`; migrations happen when state
files are missing. `omarchy update` runs `omarchy-migrate` after the package
transaction in the already-visible update terminal, then runs
`omarchy-hook post-update`.

## First-run (`omarchy-first-run`)

Runs once on first interactive login, after the user manager is live. Used
for steps that need a running graphical session and/or a working user
systemd instance:

- `omarchy-hook-install post-update install-voxtype.hook` — register the
  Voxtype post-update hook.
- `install/user/first-run/enable-user-units.sh` — `systemctl --user enable`
  the shipped user units (`bt-agent`, `omarchy-sleep-lock`,
  `omarchy-recover-internal-monitor`, `omarchy-update-user-notify.path`). Done here, not at finalize, because
  the user manager isn't reachable from the ISO chroot; `ConditionPath*`
  in the unit files keeps services inert when they don't apply.
- `install/user/first-run/gnome-theme.sh`,
  `install/user/first-run/gtk-primary-paste.sh` — GNOME/GTK settings that
  need the dconf daemon.
- `install/user/first-run/welcome.sh`,
  `install/user/first-run/wifi.sh` — welcome and Wi-Fi/update toasts
  (waits for a live notification server before firing).

Idempotency marker: `~/.local/state/omarchy/first-run-user.done`. On
failure the marker is not written and the failed step retries next login.

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
nvim refresh. Destructive: existing user files copied from `/etc/skel` are
clobbered without backup. Fastfetch is package-owned at
`/etc/fastfetch/config.jsonc`; delete `~/.config/fastfetch/config.jsonc` to
return to the packaged default.

## Quick reference: where does X live?

| Goal | Touch |
| --- | --- |
| Default file at `~/.config/foo/` | `config/foo/` |
| `/etc/` drop-in we own outright | `etc/` |
| `/etc/` file owned by an upstream package | `default/`, then add to `etc-overrides` in `omarchy-settings` PKGBUILD + scriptlet |
| Package-owned system file (e.g. systemd user service/path in `/usr/lib`) | `default/`, document the mapping in `default/package-defaults.tsv`, then add the `install -Dm644` line in `omarchy-settings` PKGBUILD |
| Per-user file that's static but lives outside `~/.config` | `default/`, then add `install -Dm644 ... $pkgdir/etc/skel/...` in `omarchy-settings` PKGBUILD |
| Runtime tweak that needs `$HOME` or live system state | extend `omarchy-finalize-user`, or add a per-user leaf under `install/user/` and wire into `install/user/all.sh` |
| One-time root-side setup step | `install/config/*.sh` or `install/hardware/*.sh`, wire into `omarchy-setup-system` or `install/hardware/all.sh` |
| One-time fix for existing installs | `migrations/<unix-timestamp>.sh` |
| User-facing `omarchy-*` command | `bin/omarchy-<group>-<verb>` — see `GROUP_DESCRIPTIONS` in `bin/omarchy` |
| New stock theme | `themes/<name>/` (+ matching templates under `default/themed/` if they need theme colors) |
| User-installed theme | `~/.config/omarchy/themes/<name>/` |
| Generated current theme/background state | `~/.local/state/omarchy/current/` |
