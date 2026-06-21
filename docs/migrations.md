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

### During direct pacman updates

Raw `sudo pacman -Syu` is guarded. Users should normally run:

```bash
omarchy update
```

If a user explicitly bypasses the guard, user sessions watch the packaged
migration directory and run a notifier. The notifier checks:

```bash
omarchy-migrate --pending
```

If that user has pending migrations, it shows a notification that opens a
terminal for:

```bash
omarchy-migrate
```

The notifier never runs migrations silently in the background.

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
- Use helper commands such as `omarchy-cmd-present`, `omarchy-cmd-missing`,
  `omarchy-pkg-add`, `omarchy-pkg-drop`, `omarchy-pkg-present`, and
  `omarchy-pkg-missing` when appropriate.

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
