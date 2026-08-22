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

## Rules

- Power User Mode must never be framed as "advanced because you're smart" — it is just a different workflow over the same platform.
- Switching modes must not require a reboot or lose user state.
- Every Desktop Mode surface stays reachable in Power User Mode unless it directly contradicts a tiling-first assumption.
