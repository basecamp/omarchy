# Mode Profiles

One toggle, two profiles, one underlying platform:

- **Desktop Mode** (default) — floating windows, taskbar, Start menu, desktop icons, visible affordances everywhere. Zero terminal ownership, zero hotkey prerequisites.
- **Power User Mode** — tiling-first layout, Omarchy's Super-key bindings, workspace-centric navigation, raw config editing, original Omarchy menu, optional top bar.

Do not build two operating systems. A profile is a set of feature flags and defaults over the same shell, services, and theme system.

## Schema

`default/ultimate/profiles/<mode>.json`:

```text
mode                     profile identifier ("desktop" | "power-user")
description              one-line human summary
features.desktopIcons    desktop icon surface enabled
features.taskbar         ultimate taskbar enabled
features.startMenu       ultimate Start surface enabled
features.systemTray      tray cluster in shell chrome
features.quickSettings   Quick Settings surface enabled
features.notificationCenter
features.floatingWindows windows float by default instead of tiling
features.tilingDefault   Hyprland tiling is the default layout policy
features.snapLayouts     visual snap-layout chooser on maximize hover
features.taskView        Task View / window overview surface
features.omarchyBindings Omarchy's Super-key binding set active
features.powerUserMenu   original Omarchy menu available
features.topBar          bar shown at top (Power User heritage layout)
features.configEditingExposed
                         config-file entry points surfaced in Settings
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

## Hyprland

`default/hypr/omarchy.lua` reads the same state file. Desktop Mode loads `default/hypr/bindings/desktop.lua` and `default/hypr/desktop-windows.lua` (float by default, resize on border, real maximize, Windows keybindings). Power User Mode keeps the original tiling bindings and `default/hypr/windows.lua`.

## Rules

- Power User Mode must never be framed as "advanced because you're smart" — it is just a different workflow over the same platform.
- Switching modes must not require a reboot or lose user state.
- Every Desktop Mode surface stays reachable in Power User Mode unless it directly contradicts a tiling-first assumption.
