# Omarchy update process

This document describes the intended update behavior now that Omarchy is
package-backed. It covers the blessed update path plus what happens when a user attempts to
bypass it:

1. `omarchy update` — the blessed interactive Omarchy update flow.
2. `sudo pacman -Syu` — guarded by Omarchy and aborted with instructions unless
   the user explicitly bypasses the guard.

The design goal is:

- System/root migrations should run automatically from package transactions when
  safe.
- User/session migrations should never run invisibly from pacman because they may
  need `$HOME`, DBus/session state, a graphical session, or user interaction.
- Users who bypass `omarchy update` should still get system migrations from
  pacman and should be notified only when their own user migration state is
  missing a shipped user migration.

## State and coordination files

| Path | Owner | Purpose |
| --- | --- | --- |
| `${XDG_RUNTIME_DIR:-/tmp}/omarchy-update.lock` | user | Prevent overlapping update runs. Owned by `omarchy-update`; compatibility wrappers inherit/respect it. |
| `/tmp/omarchy-update.log` | user | Transcript of `omarchy update`, used by `omarchy-update-analyze-logs`. |
| `~/.local/state/omarchy/updates/` | user | Update-check state for the shell widget (`packages`, `aur`, `available`, `checked-at`, `error`). |
| `~/.local/state/omarchy/current/` | user | Generated active theme, selected theme name, and current background symlink. |
| `/var/lib/omarchy/migrations/system/` | root | System migration markers. |
| `~/.local/state/omarchy/migrations/user/` | user | User migration markers. |
| `~/.local/state/omarchy/reboot-required` | user | Optional reboot marker checked by `omarchy-update-restart`. |
| `~/.local/state/omarchy/restart-*-required` | user | Optional service/app restart markers checked by `omarchy-update-restart`. |

## Migration layout

See [`migrations.md`](migrations.md) for the full migration model, authoring
guidelines, and troubleshooting notes.

Migrations are scoped by directory:

```text
migrations/system/*.sh
migrations/user/*.sh
```

### System migrations

System migrations are root-owned, noninteractive fixes for existing installs.
They may touch `/etc`, `/usr`, `/boot`, system services, hardware configuration,
and other machine-wide state.

Runner:

```bash
omarchy-migrate-system
```

Completion state:

```text
/var/lib/omarchy/migrations/system/<migration filename>
```

Pacman integration:

```text
pkgbuilds/omarchy/omarchy.install post_upgrade()
```

The `omarchy` package calls `omarchy-migrate-system` from `post_upgrade()`.
The runner is idempotent, so repeated calls only check the state files.

### User migrations

User migrations are current-user/session fixes. They may touch `~/.config`,
`~/.local`, user systemd units, browser/editor preferences, DBus/session state,
or ask questions.

Runner:

```bash
omarchy-migrate-user
```

Public command:

```bash
omarchy-migrate
```

Completion state:

```text
~/.local/state/omarchy/migrations/user/<migration filename>
```

A user migration is pending only when a script exists in `migrations/user/` and
that user's matching state file is missing. There is no global root-owned queue
for user migrations.

`omarchy-migrate` is the public command. It waits for any active pacman
transaction to finish, runs pending system migrations, then runs pending user
migrations. It does not need `--force`; migrations should happen when they are
pending.

For watchers and diagnostics, `omarchy-migrate --pending [all|system|user]`
prints pending migration names and exits `0` when any are pending. Output is
scope-prefixed, for example:

```text
system/100-system.sh
user/200-user.sh
```

When no matching migrations are pending, it prints nothing and exits non-zero.

## Raw pacman guard

The `omarchy` package installs an ALPM pre-transaction hook alongside its guard
binary:

```text
/usr/share/libalpm/hooks/00-omarchy-update-guard.hook
/usr/bin/omarchy-update-pacman-guard
```

It triggers on package upgrades and runs:

```bash
omarchy-update-pacman-guard
```

The guard detects direct pacman system-upgrade commands like `pacman -Syu` or
`pacman --sync --refresh --sysupgrade`. If the upgrade was not launched by an
Omarchy update command, the hook exits non-zero with `AbortOnFail`, which stops
the transaction before packages are changed.

`omarchy-update-system-pkgs`, `omarchy-refresh-pacman`, `omarchy-reinstall-pkgs`,
and the v4 upgrader run pacman through:

```bash
env OMARCHY_UPDATE_PACMAN=1 pacman ...
```

so the guard allows Omarchy-owned update flows. A user can intentionally bypass
the guard with:

```bash
sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu
```

The guard does not start `omarchy update` itself because pacman is already in a
transaction setup path; it only aborts with instructions.

The `omarchy` package also installs ALPM hooks for `omarchy-settings` /
`omarchy-settings-dev` installs and upgrades. The pre-transaction hook runs
`omarchy-hyprland-reload-guard pause` to disable live Hyprland config reloads
while `/usr/share/omarchy/default/hypr/**` is replaced. The post-transaction
hook runs `omarchy-hyprland-reload-guard resume`, forces one `hyprctl reload`,
and restores the session's previous `misc.disable_autoreload` and
`debug.suppress_errors` values.

## Path 1: `omarchy update`

High-level flow:

```text
omarchy-update
  ├─ ensure transcript logging through script(1) → /tmp/omarchy-update.log
  ├─ acquire update lock
  ├─ confirm unless -y
  ├─ create snapper snapshot, if snapper is installed
  └─ run update pipeline
       ├─ block system sleep and temporarily enable shell stay-awake mode
       ├─ omarchy-update-keyring
       ├─ omarchy-update-system-pkgs
       ├─ omarchy-migrate
       ├─ omarchy-hook post-update
       ├─ omarchy-update-aur-pkgs
       ├─ omarchy-update-mise
       ├─ omarchy-update-orphan-pkgs
       ├─ omarchy-update-analyze-logs
       ├─ omarchy-update-available, then refresh/clear shell indicator
       ├─ omarchy-update-restart
       └─ release sleep inhibitor and restore shell idle state, if changed
```

Important behavior:

- `omarchy update` checks/runs system and user migrations in the same visible
  terminal via `omarchy-migrate`.
- `omarchy update` still benefits from pacman-triggered system migrations
  because the system migration hook runs as part of the pacman transaction.
- A failure should leave enough output in `/tmp/omarchy-update.log` and the
  terminal transcript to debug.

## Path 2: direct `sudo pacman -Syu` attempt

High-level flow:

```text
sudo pacman -Syu
  ├─ pre-transaction guard aborts and tells the user to run omarchy update
  └─ if explicitly bypassed, upgrades omarchy and related packages
  ├─ omarchy post_upgrade runs omarchy-migrate-system as root
  └─ user session notices migration directory changes
       ├─ omarchy-update-user-notify.path triggers, if enabled
       ├─ omarchy-migrate-notify checks omarchy-migrate --pending user
       ├─ if this user has missing migration state, show notification
       └─ click opens terminal: omarchy-migrate
```

Fallbacks:

- `omarchy-first-run` enables the user notification path unit.
- `omarchy-first-run` also invokes `omarchy-migrate-notify` on graphical
  startup, so users who updated before the path unit existed still get prompted
  if they have missing user migration state.
- The notifier is only a prompt. It does not run user migrations in the
  background.
- Direct pacman updates do not run `omarchy-hook post-update` unless the user
  explicitly runs that hook; without a package-update marker, the only user-side
  pending state we can derive is missing user migration markers.

## Shell update indicator

The bar widget `omarchy.system-update` runs:

```bash
omarchy-update-available
```

`omarchy-update-available` uses `checkupdates` with a temporary database when
available, plus `yay -Qua` for AUR updates when foreign packages are installed.
It stores the result in:

```text
~/.local/state/omarchy/updates/packages
~/.local/state/omarchy/updates/aur
~/.local/state/omarchy/updates/available
~/.local/state/omarchy/updates/checked-at
~/.local/state/omarchy/updates/error
```

Exit codes:

- `0` — updates are available; stdout is the update list.
- non-zero — no updates are available; stdout says the system is up to date.

The widget uses the line count to show/hide itself. It also watches the
`available` state file, so manually running `omarchy-update-available` updates
the widget as soon as the file changes. Hovering the update icon opens a panel
that lists Omarchy packages first, then all other package updates.

## Update-related binaries

This inventory is intentionally opinionated. Some commands are useful as stable
leaf commands; others exist mostly because the old update flow accreted small
scripts.

| Binary | Current purpose | Keep? / Question |
| --- | --- | --- |
| `omarchy-update` | Public user command. Adds transcript logging, lock, confirmation, snapshot, sleep/idle inhibitors, package updates, migrations, hooks, update-state refresh, and restart checks. | **Keep.** This is the blessed entry point and owns the update pipeline. |
| `omarchy-update-perform` | Hidden compatibility wrapper for `omarchy-update -y`. | **Temporary.** Keep only for old callers; new code should call `omarchy-update` directly. |
| `omarchy-update-confirm` | Gum confirmation copy for `omarchy update`. | **Question.** Could be inlined into `omarchy-update`; separate file only helps keep copy isolated. |
| `omarchy-update-keyring` | Ensures Omarchy keyring and Arch keyring are current before the main transaction. | **Keep, but review.** It uses targeted `pacman -Sy` for keyring bootstrapping; acceptable for this special case but should remain tightly scoped. |
| `omarchy-update-system-pkgs` | Runs `sudo env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --noconfirm` with targeted transition `--overwrite` entries so the ALPM guard allows the transaction and early package-layout conflicts are handled. | **Keep for now.** Small leaf command, clear/testable. |
| `omarchy-migrate-system` | Runs root/system migrations from `migrations/system`. Called by `omarchy` package `post_upgrade()` and by `omarchy-migrate` when system migration state is missing. | **Keep.** This is the important direct-`pacman -Syu` integration. |
| `omarchy-migrate-user` | Checks `migrations/user` against this user's state and runs only missing user migrations. Supports `--pending` and prints pending filenames. | **Keep internal.** Public users should generally run `omarchy-migrate`. |
| `omarchy-migrate` | Public migration command. Waits for pacman, then runs pending system and user migrations. Supports `--pending [all|system|user]` and prints scope-prefixed pending filenames. | **Keep.** This replaces the discarded `omarchy-update-user-finalize` name and no longer needs `--force`. |
| `omarchy-update-pacman-guard` | ALPM pre-transaction guard that aborts direct `pacman -Syu` style upgrades unless Omarchy set `OMARCHY_UPDATE_PACMAN=1` or the user explicitly set `OMARCHY_ALLOW_DIRECT_PACMAN=1`. | **Keep internal/hidden.** This is what nudges users back to `omarchy update`. |
| `omarchy-migrate-notify` | Internal notification helper for direct pacman updates. Uses `omarchy-migrate --pending user` and shows notification only when this user has pending migrations. | **Keep internal/hidden.** Clear name now that the public command is `omarchy-migrate`. |
| `omarchy-update-user-notify` | Hidden compatibility wrapper for `omarchy-migrate-notify`. | **Temporary.** Keep only for old callers. |
| `omarchy-update-available` | Update checker for shell widget and post-update refresh. Writes update state. | **Keep.** Could eventually be renamed `omarchy-update-check`, but current name matches widget semantics. |
| `omarchy-update-aur-pkgs` | Updates AUR packages with `yay -Sua` if foreign packages exist and AUR is reachable. | **Question.** Omarchy is package-backed now, but users may still install AUR packages. Keep for now. |
| `omarchy-update-mise` | Runs `mise up` for mise-managed tools. | **Keep.** Mise-managed tools are intentionally part of the blessed update path. |
| `omarchy-update-orphan-pkgs` | Lists orphans and prompts before removal; noninteractive mode never removes. | **Keep for now.** Safe because it is prompt-only. |
| `omarchy-update-analyze-logs` | Scans `/tmp/omarchy-update.log` for known failure patterns, currently initramfs generation. | **Keep/expand.** Useful safety net; should grow only for high-signal checks. |
| `omarchy-update-restart` | Prompts for reboot after kernel/Hyprland updates and restarts components with `restart-*-required` markers. | **Keep.** Important final step; may eventually include service-restart checks. |
| `omarchy-update-firmware` | Manual firmware update command using fwupd. Not part of the normal update pipeline. | **Keep separate.** Firmware is not a routine system update step. |
| `omarchy-update-time` | Restarts `systemd-timesyncd`. | **Question.** Not really an update command. Consider renaming/moving under system/time maintenance. |

## Closed decisions

1. **System migrations run from the `omarchy` package**
   - `omarchy.install post_upgrade()` calls `omarchy-migrate-system`.
   - We do not need a separate system-migration ALPM hook from
     `omarchy-settings`.

2. **Root vs user migrations stay separate**
   - Do not use `su {user}` from pacman to run user migrations.
   - User migrations need the user's real session and should be visible.
   - Pending user work is determined only by comparing `migrations/user/*.sh`
     against `~/.local/state/omarchy/migrations/user/`.

3. **Migration notification naming**
   - The real helper is `omarchy-migrate-notify`.
   - `omarchy-update-user-notify` remains only as a hidden compatibility wrapper.

4. **Update pipeline ownership**
   - `omarchy-update` owns the full update pipeline now.
   - `omarchy-update-perform` is only a hidden compatibility wrapper for
     `omarchy-update -y`.

5. **Mise remains in the blessed update path**
   - `omarchy-update-mise` intentionally runs as part of `omarchy update`.

6. **Orphan cleanup stays in the update path for now**
   - It is prompt-only and never removes packages noninteractively.

7. **Direct pacman user follow-up is based on actual migration state**
   - Direct `sudo pacman -Syu` no longer uses a fake user-update marker.
   - User notifications are shown only when `omarchy-migrate --pending user`
     finds missing per-user migration state.

## Remaining concerns

1. **Pacman guard scope**
   - The guard detects direct pacman sysupgrade invocations and allows Omarchy
     commands that set `OMARCHY_UPDATE_PACMAN=1`.
   - We may regret blocking some legitimate package-manager frontends or
     maintenance flows. Keep an eye on what should be allowed versus redirected
     to `omarchy update`.

2. **Pacnew/pacsave handling is still missing**
   - Package-backed Omarchy should warn about or help process `.pacnew` and
     `.pacsave` files after updates.
