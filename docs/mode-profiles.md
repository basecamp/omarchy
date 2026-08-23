# Mode Profiles

One toggle, two profiles, one underlying platform:

- **Desktop Mode** (default) — floating windows, Superbar, Start, visible affordances everywhere. Zero terminal ownership, zero hotkey prerequisites. Agent Center belongs here as native as Start (not implemented yet; `omarchy.agents` must stay visible until it is).
- **Power User Mode** — tiling-first layout, Omarchy's Super-key bindings, workspace-centric navigation, raw config editing, original Omarchy menu, optional top bar.

Do not build two operating systems. A profile is a set of feature flags and defaults over the same shell, services, and theme system.

## Honesty rule

Flags mean **the capability exists in this profile today**, not "we intend to ship it." `default/ultimate/profiles/desktop.json` and `power-user.json` stay false for unimplemented surfaces. `ModeProfileService.qml` first-frame defaults must match `desktop.json`.

Verified against the tree (2026-08-22):

- `desktopIcons` is false. There is no desktop icon surface (only a gallery label).
- `quickSettings` is false. There is no Quick Settings composition. Superbar `TrayCluster.qml` hard-loads audio/bluetooth/network/monitor/power panels plus `Tray.qml` and clock — that is a notification-area cluster, not Quick Settings.
- `notificationCenter` is false. `omarchy.notifications` is a toast daemon with on-disk history (`docs/notifications.md`). That is not a Notification Center product surface.
- `taskbar` / `startMenu` are true in Desktop Mode: `omarchy.ultimate-taskbar` and `omarchy.ultimate-start` exist. They are prototypes (see doctrine honesty), not Windows 7 quality.
- `systemTray` is true: Superbar loads `bar/widgets/Tray.qml`; the heritage bar has `omarchy.tray`.
- `snapLayouts` is true: `omarchy.ultimate-snap-chooser` exists. Muscle-memory API is still maximize-hover or drag-to-edge, not a fourth caption button.
- `taskView` is true: `omarchy.ultimate-task-switcher` has a `taskView` mode (desktop list + window titles). It is not Windows Task View quality.

Runtime `feature()` call sites today are only `shell.qml` (`taskbar` / `topBar` overlay) and `Start.qml` (`developerToolsInStart`). The other flags are honesty data, not live gates.

## Schema

`default/ultimate/profiles/<mode>.json`:

```text
mode                     profile identifier ("desktop" | "power-user")
description              one-line human summary
features.desktopIcons    desktop icon surface enabled
features.taskbar         ultimate Superbar enabled
features.startMenu       ultimate Start surface enabled
features.systemTray      tray cluster in shell chrome
features.quickSettings   Quick Settings surface enabled
features.notificationCenter
                         Notification Center surface enabled (not the toast daemon)
features.floatingWindows windows float by default instead of tiling
features.tilingDefault   Hyprland tiling is the default layout policy
features.snapLayouts     visual snap-layout chooser exists
features.taskView        Task View / window overview surface exists
features.omarchyBindings Omarchy's Super-key binding set active
features.powerUserMenu   original Omarchy menu available
features.topBar          bar shown at top (Power User heritage layout)
features.configEditingExposed
                         config-file entry points surfaced in Settings
features.developerToolsInStart
                         Terminal, Vim, and other developer tools appear in the idle Start list. Desktop Mode keeps them searchable, not first class.
```

## Resolution order

User choice (`~/.local/state/omarchy/ultimate/mode`) wins over the shipped default (`desktop.json`). Services read the effective profile; UI surfaces register against feature flags rather than checking mode strings directly, so adding a third profile later is a data change, not a refactor.

The CLI is `omarchy mode`:

```text
omarchy mode get
omarchy mode set desktop
omarchy mode set power-user
```

`set` writes the state file, reloads Hyprland, and restarts the shell so bindings and chrome swap together. `OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1` skips the reload for tests. Start's footer toggle writes the same file through `ModeProfileService` and reloads Hyprland without a reboot.

## Shell overlay

Desktop Mode does not rewrite `~/.config/omarchy/shell.json`. `shell.qml` computes an effective config: when `features.taskbar` is on and `features.topBar` is off, `bar.id` becomes `omarchy.ultimate-taskbar` and `bar.position` becomes `bottom`. Plugin enable/disable and Settings still persist the on-disk file, so switching back to Power User Mode restores the heritage bar without a migration.

That overlay currently **sets a Desktop Mode notification-area layout** that includes `omarchy.agents`, without writing it to disk. Superbar `TrayCluster.qml` loads those ids from `barConfig` through `BarWidgetRegistry`. Preserve the Quattro plugin model under Windows-quality Superbar presentation. Until Agent Center exists, `omarchy.agents` stays visible in Desktop Mode (empty-state copy if no usage files).

## Hyprland

`default/hypr/omarchy.lua` reads the same state file. Desktop Mode loads `default/hypr/bindings/desktop.lua` and `default/hypr/desktop-windows.lua` (float by default, resize on border, real maximize, Windows keybindings). Power User Mode keeps the original tiling bindings and `default/hypr/windows.lua`.

## Rules

- Power User Mode must never be framed as "advanced because you're smart" — it is just a different workflow over the same platform.
- Switching modes must not require a reboot or lose user state.
- Every Desktop Mode surface stays reachable in Power User Mode unless it directly contradicts a tiling-first assumption.
- Agent Center is a Desktop Mode surface. Do not hide agents in Power User Mode.
