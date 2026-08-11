# Automation Hooks

Use this guide for scripts triggered by theme changes, updates, boot, battery, or
other Omarchy events.

## Hook Shape

Hooks live under `~/.config/omarchy/hooks/`:

```text
~/.config/omarchy/hooks/<name>       # Optional legacy single script; runs first
~/.config/omarchy/hooks/<name>.d/    # Independent scripts; run in filename order
```

Install a script into the directory form:

```bash
omarchy hook install <name> <script>
```

The installer copies the script and makes the installed copy executable. Use a
portable `#!/bin/bash` script and handle the event arguments documented below.

| Event | Timing and arguments |
|---|---|
| `battery-low` | Low battery; percentage in `$1` |
| `font-set` | After a font change; font name in `$1` |
| `post-boot` | After the desktop starts |
| `post-update` | After system packages and migrations, before AUR, Mise, and orphan-package updates |
| `pre-refresh-pacman` | Before `omarchy refresh pacman` resynchronizes packages |
| `theme-set` | After a theme change; theme slug in `$1` |

## Implementation Loop

1. Inspect existing scripts under the target hook name so the new script has one responsibility and a distinct filename.
2. Run the source script directly with representative arguments.
3. Install it with `omarchy hook install`.
4. Invoke a safe hook directly with `omarchy hook <name> [args...]`, or trigger the real event when direct invocation would not represent its environment.
5. Observe the intended side effect and inspect any script output or logs.

Example:

```bash
#!/bin/bash
set -e

theme_name=$1
printf 'Theme changed to: %s\n' "$theme_name"
```

Hook work is complete when the installed copy exists under the intended
`<name>.d/`, representative execution exits successfully, and the intended side
effect has been observed. Report any real event that was unsafe or impractical
to trigger as unverified.

## Recovery

Disable a hook by moving its user-owned script outside the hook directory;
restore it by moving the same file back. Obtain confirmation before deleting a
user script. Recovery is complete when `omarchy hook <name> [args...]` no
longer runs the removed behavior while other scripts for that event still run.
