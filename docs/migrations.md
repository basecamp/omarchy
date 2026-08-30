# Omarchy migrations

Omarchy migrations are one-time repair scripts for existing installs. They are
used when a package update needs to change state that pacman cannot safely own by
itself.

## Migration model

Migrations live in:

```text
migrations/*.sh
```

They run as the current Omarchy user through `omarchy-migrate`, normally during
`omarchy update`. A migration may touch user/session state (`~/.config`,
`~/.local`, user systemd, browser/editor prefs, DBus/session state), and may also
perform machine-wide repairs when needed.

Completion state is per-user:

```text
~/.local/state/omarchy/migrations/<migration filename>
```

That means every user gets a chance to run every migration. Migrations run as the
user; privileged operations should invoke the appropriate helper or privilege
prompt themselves. Migrations must be idempotent: if one user already applied a
machine-wide repair, the same migration running for another user should detect
that and no-op.

## When migrations run

### During `omarchy update`

`omarchy update` is the normal update path. It runs package updates, then:

```bash
omarchy-migrate
omarchy-hook post-update
```

`omarchy-migrate` waits for any active pacman transaction to finish, then runs
all pending migrations for the current user in the visible update terminal.

### At login

Every graphical login starts `omarchy-migrate-notify.service` after
`graphical-session.target`. The notifier checks:

```bash
omarchy-migrate --pending
```

It stays silent while `omarchy update` holds its lock, since that update applies
the pending migrations itself.

If that user has pending migrations, it shows a notification that opens a
terminal for:

```bash
omarchy-migrate
```

The notifier never runs migrations silently in the background.

This is what covers users who did not run the update themselves: someone who
bypassed the pacman guard with `sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman
-Syu`, and any second user on the machine, whose migration markers are per-user
and therefore still missing after another user updated.

Login is the only trigger on purpose. Watching the packaged migration directory
also fires during a normal `omarchy update`, which prompts for migrations that
`omarchy-migrate` is about to run in the visible update terminal.

### Manually

Users can safely run:

```bash
omarchy-migrate
```

at any time. Already-completed migrations are skipped.

## Inspecting pending migrations

Use:

```bash
omarchy-migrate --pending
```

Exit behavior:

- `0` — one or more migrations are pending
- non-zero — no migrations are pending

Output is one pending migration per line:

```text
1781158082.sh
```

## Creating a migration

Use the helper:

```bash
omarchy-dev-add-migration --no-edit
```

This creates:

```text
migrations/<unix timestamp>.sh
```

New migration format:

- File permissions must be `0644` (`-rw-r--r--`). Migration runners execute them
  with `bash -euo pipefail`, not through executable bits.
- No shebang line.
- Start with an `echo` describing what the migration does.
- Use `$OMARCHY_PATH` to reference the Omarchy directory.
- Be idempotent. Check existing state before changing it.
- Migrations are strictly ordered and synchronous. A migration that cannot finish must exit non-zero, remain pending, and stop the queue; never mark later migrations complete against state an earlier migration has not established.
- Use helper commands such as `omarchy-cmd-present`, `omarchy-cmd-missing`,
  `omarchy-pkg-add`, `omarchy-pkg-drop`, `omarchy-pkg-present`, and
  `omarchy-pkg-missing` when appropriate.
- Never restart the Omarchy shell. `omarchy update` restarts it unconditionally
  after migrations run, and the login-time shell already runs current code and
  hot-reloads `shell.json` edits.
- Raw `pacman`, `command -v`, and direct config edits are acceptable when
  needed for one-off repair work.

Example:

```bash
echo "Relink Neovim theme to Omarchy current state"

theme_link="$HOME/.config/nvim/lua/plugins/theme.lua"
current_relative_target="../../../../.local/state/omarchy/current/theme/neovim.lua"

[[ -L $theme_link ]] || exit 0
ln -sfn "$current_relative_target" "$theme_link"
```

## Testing migrations

Run a migration against a temporary home when possible:

```bash
HOME=$(mktemp -d) bash -euo pipefail migrations/<timestamp>.sh
```

To rerun a migration locally, remove its marker and run the migrator:

```bash
rm ~/.local/state/omarchy/migrations/<migration>.sh
omarchy-migrate
```

Omarchy 4.0 is upgraded through `bin/omarchy-upgrade-to-quattro`, not through the
normal migration runner. Do not add compatibility migrations for old installer
layouts; put pre-4 package-layout transition work in the upgrade command instead.

Clearing a privileged file that a retired installer left on disk is the exception, and belongs in a migration whether or not that installer was part of a package layout transition. The upgrade command only runs on a machine still making the 3 to 4 crossing, so anything put there never reaches an install that crossed already, and it never runs at all for an installer that was retired on its own — while the file the installer wrote is still sitting on those machines. The upgrade command finishes by running `omarchy-migrate` (`run_post_upgrade_migrations`), so one migration reaches every population; a copy in the upgrade command would only be a second copy of the same predicate to keep correct. Such a migration must name the defect it clears and match what the old installer actually produced before deleting it. Leave safe administrator-authored files alone; if one still contains the vulnerable privileged action, preserve it under an inactive name rather than discarding custom content or leaving the action executable. A user config that depends on the same retired compatibility path may be repaired in that migration when doing so eliminates an overlapping migration, but only by matching and replacing the exact legacy path while preserving the rest of the file.
