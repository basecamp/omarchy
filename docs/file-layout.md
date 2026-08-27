# File layout

How `omarchy/` is organized and where everything ends up on an installed
system.

## Mental model

Two Arch packages are built from this one repo (PKGBUILDs live in the
separate `omarchy-pkgs` repository, under `pkgbuilds/`):

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

Two other packages live in `omarchy-pkgs` but stand alone:
`omarchy-keyring` (GPG keys for pacman) and `omarchy-nvim` (the Neovim
setup; independently seeds `/etc/skel`).

Some trees ship in neither package and exist only in the repo: `manual/`
(user manual chapters), `agents/skills/` (contributor task guides), `docs/`,
`test/`, and `plans/`.

Three layers populate `$HOME`:

1. **Seed** — `omarchy-settings` ships static defaults to `/etc/skel/`.
   Arch's `useradd -m` copies that tree into a new user's `$HOME` at user
   creation. This is the only mechanism that touches a brand-new user's home
   for these files.
2. **Finalize** — `omarchy-provision-user` (routed as `omarchy finalize
   user`) runs once per user and handles the things `/etc/skel` can't do
   because they need `$HOME` expansion, the live `$OMARCHY_PATH`, or runtime
   detection of system state.
3. **Resync** — `omarchy-reinstall-configs` is the explicit, destructive
   command for an existing user to clobber their configs back to shipped
   defaults.

`/etc/skel` only fires at user creation. Existing users picking up new
defaults must use the resync command.

Deferred-provisioning installs (`omarchy-apply-system --defer-provisioning`)
create no user at all: the ISO leaves `/var/lib/omarchy/provisioning/pending`
behind, which arms `omarchy-provision-owner.service` (shipped from
`install/provisioning/`, alongside the factory-reset finish unit and
`setup-form.sh`). On first boot `bin/omarchy-provision-owner` creates the
user on tty1 and runs the finalize step itself.

Current generated theme state lives under
`~/.local/state/omarchy/current/`. Keep `~/.config/omarchy/` for files a user
may intentionally version in a dotfile manager, such as user themes, hooks,
shell layout, plugins, and themed template overrides.

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
default/applications/battlenet.desktop
                                ──►  omarchy-settings    /usr/share/omarchy/default/applications/
                                                        (installer-only launcher template)
applications/icons/*           ──►  omarchy-settings    /usr/share/icons/hicolor/{48,256,scalable}/apps/

etc/**                         ──►  omarchy-settings    /etc/**           (drop-ins we own outright)
  ├─ mkinitcpio.conf.d/{omarchy_hooks,thunderbolt_module}.conf
  ├─ limine-entry-tool.d/{omarchy-defaults,omarchy-uki}.conf
  ├─ NetworkManager/, sudoers.d/, sysctl.d/, tmpfiles.d/,
  │  profile.d/omarchy.sh, …                            (a summary — `ls etc/` for the full ~17-entry tree)
  └─ security/faillock.conf, nsswitch.conf,
     cups/cups-browsed.conf, plymouth/plymouthd.conf    /usr/share/omarchy/etc-overrides/
                                                          → /etc/* (post_install cp -f, see below)

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
  ├─ hypr/toggles/*.lua (flags,
  │    single-window-aspect-ratio, window-no-gaps)      /etc/skel/.local/state/omarchy/toggles/hypr/
  ├─ nautilus-python/extensions/*.py                    /etc/skel/.local/share/nautilus-python/extensions/
  ├─ tensaku/state.toml                                 /etc/skel/.local/state/tensaku/state.toml
  ├─ uwsm/env.d/10-omarchy                              /usr/share/uwsm/env.d/
  ├─ environment.d/*.conf                               /usr/lib/environment.d/
  ├─ fontconfig/conf.avail/50-omarchy.conf              /usr/share/fontconfig/conf.avail/
  │                                                       + symlink /etc/fonts/conf.d/50-omarchy.conf
  ├─ xdg-terminal-exec/*.list                           /usr/share/xdg-terminal-exec/
  ├─ applications/mimeapps.list                         /usr/share/applications/mimeapps.list
  ├─ systemd/user/*.service                             /usr/lib/systemd/user/
  ├─ systemd/user/app.slice.d/10-oomd.conf              /usr/lib/systemd/user/app.slice.d/
  ├─ systemd/system-sleep/{force-igpu,
  │    keyboard-backlight,unmount-fuse}                 /usr/lib/systemd/system-sleep/
  ├─ systemd/zram-generator.conf.d/90-omarchy.conf      /usr/lib/systemd/zram-generator.conf.d/
  ├─ fonts/omarchy/omarchy.ttf                          /usr/share/fonts/omarchy/
  ├─ sddm/omarchy/                                      /usr/share/sddm/themes/omarchy/
  ├─ sddm/hyprland.lua                                  /usr/share/sddm/hyprland.lua
  ├─ wayland-sessions/omarchy.desktop                   /usr/local/share/wayland-sessions/
  └─ plymouth/                                          /usr/share/plymouth/themes/omarchy/

logo.{txt,svg}, icon.{txt,png}  ──► omarchy-settings    /usr/share/omarchy/  (resync source)
                                                        /usr/share/pixmaps/omarchy.png
                                                        /usr/share/icons/hicolor/256x256/apps/omarchy.png
                                                        /etc/skel/.config/omarchy/branding/{about,screensaver}.txt
```

### Why `etc-overrides/` exists

Some files under `/etc/` (`.bashrc` in `/etc/skel`, `nsswitch.conf`,
`security/faillock.conf`, `cups/cups-browsed.conf`, `plymouth/plymouthd.conf`)
are owned by upstream Arch packages, so we can't install over them via pacman
without a file conflict. Instead their sources (under `etc/` in the repo;
`.bashrc` from `default/bashrc`) ship at
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
- Appends `~/.local/share/mise/shims` and `~/.local/bin` so login shells and
  the uwsm session find mise-managed tools — kept in sync with the PAM `PATH`
  line written by `install/config/ssh-command-path.sh`, which covers SSH
  commands that run no shell setup at all.

Sourced by every entry point that needs the env set:

```
/etc/profile.d/omarchy.sh                      (system login shells)
/etc/skel/.bashrc                              (interactive shells)
/usr/share/uwsm/env.d/10-omarchy               (Hyprland session via uwsm)
/usr/share/omarchy/default/bash/envs           (SSH / non-login bash)
```

Idempotent — safe to source more than once in the same shell.

`PATH` covers everything the user runs, but not `sudo`, which resolves command
names against `secure_path` from `/etc/sudoers`. So `omarchy-dev-link` also
writes `/etc/sudoers.d/omarchy-dev-path`:

```
Defaults secure_path="<checkout>/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"
```

Without it, `sudo omarchy-*` fails for a command the package has not shipped
yet and silently runs the packaged copy of one it has. The drop-in is validated
with `visudo -c` before install and removed by `omarchy-dev-unlink`; unlike
`/etc/omarchy.conf`, it takes effect without a reboot.

## Runtime finalization (`omarchy-provision-user`)

Runs once per user. It does **not** copy `~/.config/**`, `~/.bashrc`,
`flags.lua`, or the nautilus extensions — `/etc/skel` already seeded those.
It only does the things `/etc/skel` can't:

- Skill symlinks `~/.{agents,claude,codex,pi/agent}/skills/<name>` →
  `$OMARCHY_PATH/default/agents/skills/<name>`, looping over every skill
  directory there (currently `omarchy` and `diagnose-crash`) so new skills
  need no edit. Symlinks (not copies) so `omarchy dev link` against a dev
  checkout repoints them correctly.
- `xdg-user-dirs-update` (Templates/Public/Desktop folded back into `$HOME`)
  and `~/.config/gtk-3.0/bookmarks` (needs `$HOME` expansion).
- Hyprland's package-owned default input reads `XKBLAYOUT` / `XKBVARIANT`
  from `/etc/vconsole.conf`; no per-user Hyprland config rewrite is needed.
- `xdg-settings set default-web-browser chromium.desktop` and
  `xdg-mime default HEY.desktop x-scheme-handler/mailto` (XDG-aware paths).
- `omarchy-refresh-applications` (composes generated `.desktop` launchers).
- Sources `install/user/all.sh` — theme, chromium, git, xcompose, mise,
  keyring, per-user hardware quirks (asus mic/mixer, framework f13 audio, …).
- On `--first-install`, marks every shipped user migration as already applied
  for the freshly-created user.

Idempotency marker: `~/.local/state/omarchy/done/finalize-user`, managed
by `omarchy-done`.

The ISO calls it as `omarchy-provision-user --force --first-install` in the
target chroot as the install user, after `omarchy-apply-system` has finished
the root-side work. `omarchy-provision-owner` makes the same call (with
`OMARCHY_SETUP_CONTEXT=provision-owner`) when it creates the user during
deferred first-boot provisioning.

## Migrations (`omarchy-migrate`)

See [`migrations.md`](../agents/skills/migrations.md) for the full migration model, authoring
guidelines, and troubleshooting notes.

Omarchy migrations live in `migrations/*.sh` and run per-user through
`omarchy-migrate`. Completion state lives in
`~/.local/state/omarchy/migrations/`, so every user gets a chance to run every
migration. Migrations run as the user; privileged work should invoke the
appropriate helper or privilege prompt. Migrations must be idempotent;
machine-wide repairs should no-op when another user already applied them.

Each graphical user has `omarchy-migrate-notify.service`, started once per login
through `WantedBy=graphical-session.target` and ordered after that target so
notification actions can safely launch through UWSM. The `omarchy-pkgs`
PKGBUILD has shipped `omarchy-update-user-notify.service` as a symlink onto
it, so users enabled under the old unit name keep working before they reach
migration `1785095882`.
It runs `omarchy-migrate-notify` as
that user, which checks `omarchy-migrate --pending`. If this user has missing
migration state, it shows a notification that opens a terminal for
`omarchy-migrate`. The notifier never runs migrations in the background.

Login is the only trigger. Nothing watches the packaged migration directory: a
watcher cannot tell a bypassed `pacman -Syu` from the package transaction inside
a normal `omarchy update`, so it notified about migrations that `omarchy-migrate`
was already applying in the visible update terminal.

`omarchy-migrate` waits for any active pacman transaction to finish, then runs
pending migrations. It does not need `--force`; migrations happen when state
files are missing. `omarchy update` runs `omarchy-migrate` after the package
transaction in the already-visible update terminal, then runs
`omarchy-hook post-update`.

## First-run (`omarchy-provision-first-run`)

Runs once on first interactive login, after the user manager is live. It
first runs `omarchy-provision-user || true` so finalize catches up if it
never ran, then handles the steps that need a running graphical session
and/or a working user systemd instance:

- `omarchy-hook-install post-update` for the three shipped hooks
  (`install-voxtype.hook`, `setup-fingerprint.hook`, `setup-agent.hook`).
- `install/user/first-run/enable-user-units.sh` — daemon-reload, then
  `systemctl --user enable --now` the shipped user units (`bt-agent`,
  `omarchy-sleep-lock`, `omarchy-recover-internal-monitor`,
  `omarchy-migrate-notify.service`, `omarchy-fcitx5.service`,
  `omarchy-crash-watch.service`) so they run in the first session too.
  Done here, not at finalize, because
  the user manager isn't reachable from the ISO chroot; `ConditionPath*`
  in the unit files keeps services inert when they don't apply.
- `install/user/first-run/gnome-theme.sh`,
  `install/user/first-run/gtk-primary-paste.sh` — GNOME/GTK settings that
  need the dconf daemon.
- `install/user/first-run/audio-tuning.sh` — apply speaker tuning.
- `install/user/first-run/welcome.sh` — keybindings toast that greets the
  first login and opens the cheatsheet when clicked. The caller runs
  `omarchy-notification-wait` once before this and the Wi-Fi step, so both
  toasts land on a live notification server.
- `install/user/first-run/wifi.sh` — Wi-Fi/update toasts (waits detached on
  `nm-online` so the update prompt only lands once there is a connection).

The entire sequence has one idempotency marker:
`~/.local/state/omarchy/done/first-run-user`, managed by `omarchy-done`.
Completed users exit before any first-run step. On failure the marker is not
written and the sequence retries next login.

Completion markers live under `~/.local/state/omarchy/done/`. Use
`omarchy-done check <name>` to check one and `omarchy-done mark <name>` to record it.
Use `omarchy-done ensure <name>` as a conditional when the guarded work should
run only once; it records completion before returning success.
The Quattro upgrade completes graphical first-run for upgraded users and moves
the legacy finalization marker from `~/.local/state/omarchy/` into `done/`.

## Root-side install orchestration

`omarchy-apply-system` (root, in chroot) runs target-side setup at ISO
finalization. It sources:

- `install/config/all.sh` — theme links, lockout limits, lockscreen PAM,
  powerprofilesctl shebang fix, SSH command path and keepalive, docker setup,
  Snapper retention, locate index tuning, service enablement, firewall.
- `install/hardware/all.sh` via `omarchy-apply-hardware` — vendor- and
  device-specific kernel modules, udev rules, microcode, wireless regdom,
  ASUS / Framework / Intel / Apple / Lenovo quirks.
- `install/login/all.sh` — SDDM theme/session config.
- `install/post-install/all.sh` — final pacman/udev/localdb passes.

Logging goes to `/var/log/omarchy-install.log` via
`install/helpers/logging.sh`.

The package lists the ISO pacstraps live at `install/omarchy-base.packages`
and `install/omarchy-other.packages`; the ISO builder also reads them when
constructing its offline mirror.

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
| `/etc/` file owned by an upstream package | `etc/` (see `etc/security/faillock.conf`), then add to `etc-overrides` in `omarchy-settings` PKGBUILD + scriptlet |
| Package-owned system file (e.g. systemd user service in `/usr/lib`) | `default/`, then add the `install -Dm644` line in `omarchy-settings` PKGBUILD |
| Per-user file that's static but lives outside `~/.config` | `default/`, then add `install -Dm644 ... $pkgdir/etc/skel/...` in `omarchy-settings` PKGBUILD |
| Runtime tweak that needs `$HOME` or live system state | extend `omarchy-provision-user`, or add a per-user leaf under `install/user/` and wire into `install/user/all.sh` |
| One-time root-side setup step | `install/config/*.sh` or `install/hardware/*.sh`, wire into `install/config/all.sh` or `install/hardware/all.sh` |
| One-time fix for existing installs | `migrations/<unix-timestamp>.sh` |
| Package-owned path something else may already write | Prefer a path nothing else writes, such as a vendor drop-in under `/usr/lib`. Otherwise the `--overwrite` entry in `bin/omarchy-update-system-pkgs` has to ship a release before the file |
| User-facing `omarchy-*` command | `bin/omarchy-<group>-<verb>` — see `GROUP_DESCRIPTIONS` in `bin/omarchy` |
| New stock theme | `themes/<name>/` (+ matching templates under `default/themed/` if they need theme colors) |
| User-installed theme | `~/.config/omarchy/themes/<name>/` |
| Generated current theme/background state | `~/.local/state/omarchy/current/` |
