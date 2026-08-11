---
name: omarchy
description: >
  REQUIRED on Omarchy for agent-driven OS operation and customization. Use for
  Omarchy commands, packages, updates, setup, reminders, and power actions;
  Hyprland keybindings, window rules, monitors, workspaces, animations, gaps,
  borders, blur, opacity, input, night light, and screen sharing; Quickshell
  bar, widgets, plugins, notifications, menus, idle, and lock behavior; themes,
  backgrounds, wallpapers, colors, and fonts; Alacritty, Foot, Kitty, and
  Ghostty configuration; hooks; screenshots, recordings, OCR, transcoding,
  LocalSend, and Taildrop; troubleshooting; and issue reporting. For upstream
  source work, clone basecamp/omarchy and follow its AGENTS.md instead.
---

# Omarchy System Operations

Operate an installed Omarchy system on the user's behalf. Assume the agent may
start in any directory without an Omarchy source checkout. Discover the live
system before acting. Installed-system evidence governs operations; repository
conventions begin after an upstream-development handoff.

## Operating Loop

### 1. Route

Read every guide matching the request before acting:

- **System** — read [`system.md`](system.md) for packages, optional software, updates, setup, reminders, lock, logout, reboot, or shutdown.
- **Hyprland** — read [`hyprland.md`](hyprland.md) for keybindings, monitors, window rules, input, appearance, night light, or screen sharing.
- **Shell and plugins** — read [`plugins.md`](plugins.md) for the bar, widgets, notifications, menus, plugins, idle, or lock behavior.
- **Themes** — read [`theming.md`](theming.md) for themes, backgrounds, colors, or fonts.
- **Terminals** — read [`terminals.md`](terminals.md) for Alacritty, Foot, Kitty, or Ghostty configuration.
- **Hooks** — read [`hooks.md`](hooks.md) for automation triggered by theme, update, boot, battery, or other system events.
- **Capture and sharing** — read [`capture.md`](capture.md) for screenshots, recordings, OCR, transcoding, LocalSend, or Taildrop.
- **Troubleshooting** — read [`troubleshooting.md`](troubleshooting.md) when behavior is broken, uncertain, or needs resetting.
- **Bug reports** — read [`reporting-issues.md`](reporting-issues.md) when reporting a bug, requesting a feature, seeking support, or handing work to the upstream repository.

Routing is complete when every branch in the request has its matching guide in
context. A multi-part request may require several guides.

### 2. Inspect

Inspect the current user state, the relevant command's `--help`, and packaged
defaults or command source before choosing a change. Prefer live evidence over
memorized Omarchy or Hyprland behavior.

Inspection is complete when the current value, the user-owned target, and the
supported apply or reload mechanism are known.

### 3. Change

Prefer a user-facing `omarchy` command when it expresses the requested change.
Otherwise write the smallest durable override under the user-owned locations
named below. Before directly editing an existing configuration file, preserve
a timestamped copy unless the operation already creates its own backup.

The change is complete when it lives in user-owned state and packaged files
remain untouched.

### 4. Apply and Verify

Apply the component-specific reload from the matching guide, then exercise the
requested behavior. Run every relevant validator and resolve reported errors.
If the harness cannot observe a visual or interactive result, report that part
as unverified and name the exact check the user should perform.

Verification is complete when the requested behavior is observed, relevant
validators are clean, and no requested branch remains untested or explicitly
marked unverified.

### 5. Report

Tell the user:

- what changed and where;
- what command or observation verified it;
- any part that remains unverified;
- how to reverse the change.

## State Ownership

Use these ownership boundaries on every task:

| State | Location | Agent behavior |
|---|---|---|
| User configuration | `~/.config/` | Write durable customizations here. |
| User Omarchy data | `~/.config/omarchy/` | Store themes, plugins, hooks, shell overrides, and extensions here. |
| Packaged Omarchy | `$OMARCHY_PATH` (normally `/usr/share/omarchy`) | Read commands and defaults here; package updates replace this tree. |
| System configuration | `/etc/`, system services, packages | Change only when the request requires it and use the privilege rules below. |

Treat packaged Omarchy as reference material. Read it freely to understand a
command or copy a default, while keeping durable changes in user-owned state.
For example:

```bash
omarchy theme set --help
command -v omarchy-theme-set
cat "$(command -v omarchy-theme-set)"
cat "$OMARCHY_PATH/config/omarchy/shell.json"
```

## Command Discovery

Use the public `omarchy <group> <action>` interface. Discover current commands
instead of maintaining an exhaustive command list in this skill:

```bash
omarchy commands                 # Documented commands
omarchy commands --all           # Include hidden commands
omarchy commands --json          # Machine-readable routes and metadata
omarchy <group> --help            # Commands in one group
omarchy <group> <action> --help   # Arguments for one command
```

Read the resolved `omarchy-*` executable when help does not explain behavior.

## Privilege Escalation

Run privileged work with `sudo` when a visible terminal can accept the user's
password. Use `pkexec` when the caller has no interactive terminal, such as a
graphical background process or an agent command that cannot accept input.
Commands that manage their own elevation should be invoked directly.

Privilege handling is complete when the narrowest required command ran through
an available authentication path without broadening permissions.

## Resets and Destructive Operations

`omarchy refresh <component>` replaces user configuration with packaged
defaults and normally creates a backup. Obtain confirmation immediately before
running a refresh, reinstall, package removal, or other operation that discards
or replaces user state. State the affected path and available recovery first.

Use [`troubleshooting.md`](troubleshooting.md) to diagnose before resetting.
A reset is complete only when its backup exists and the restored component has
been applied and verified.

## Upstream Source Work

Installed-system operation and upstream development are separate contexts. For
an upstream code change, clone or fork `basecamp/omarchy`, enter that checkout,
and follow its `AGENTS.md` and task guides. Continue using this skill only for
changes or verification performed against the user's installed system.
