# Project Ultimate — product plan

This is the working plan for the fork. It is not a theme plan. It is not a “move the bar to the bottom” plan. The source of the product is the Project Ultimate doctrine Jesse locked: Windows 7’s information architecture, Windows 11’s visual restraint, Quattro’s shell, Linux underneath, original 2026 design language on top.

Read this file together with:

- `PRODUCT_DOCTRINE.md` — the seven rules
- `WINDOWS_NATIVE_ACCEPTANCE.md` — the forty-task release gate
- `docs/mode-profiles.md` — Desktop Mode vs Power User Mode as flags, one platform
- `docs/settings-service-api.md` — UI → typed service → Omarchy/system tooling
- `docs/design-tokens.md` — semantic surfaces, not a Tokyo Night restyle
- `plans/desktop-mode-handoff.md` — local QEMU guest contract for the windowing slice only

If those documents and this plan disagree, the doctrine wins. If this plan and a PR description disagree, this plan wins. Do not take PR #1’s old “Windowing go/no-go — GO” as accepted; that writeup was rejected.

## Reviewer lock (2026-08-22)

Keep `4ea1dcf3` + `a5b945da`. Those are the accepted repair. Do not re-bench that pair. Keep `eddd0b57` and `9d80ecd6`. Keep `aaf601ca` (hyprbars + omarchy-minimize built into `/usr/lib/hyprland-plugins`, no hyprpm). Keep `5942beaa` (idle Start is Chrome and Files; foot and vim stay installed and searchable, they are not the front of the OS). The last two commits stay (`5942beaa`, `a4a046b3`). Do not amend them. Do not squash them.

The product call is still **REJECTED**. Windowing is still not a go. Bench stays idle.

What actually moved:

- Title bars and hide survive a wiped user cache. Live maps are `/usr/lib/hyprland-plugins/hyprbars.so` and `/usr/lib/hyprland-plugins/omarchy-minimize.so`.
- Minimize is `CWindow::setHidden` on the same workspace, not `special:minimized`. Overlay chrome is still gone.
- The QEMU postage stamp was virtio-vga coming up `640×480`; grim at 1080p was a lie. The GTK window is the proof.
- SearchBox using Qt’s stock white field was a real Start bug.

What did not move:

- hyprbars is still not an ISO-mirror pacman package. The AUR name `hyprland-plugin-hyprbars` still must not go in `install/omarchy-other.packages`.
- Alt+Tab address-change is still not a held number this lock will accept. `a4a046b3` stays; do not treat its helper addresses as a locked gate.
- This guest Start only listing foot and vim is a disk contents problem, not a reason to make the terminal first-class.
- Tokyo Night, generic gear icons, Nautilus, nvim, TTY first-boot, no product ISO — still open.
- Chrome, games, and “install any Windows app” are still not a live path.

Plans still win: `PRODUCT_DOCTRINE.md` plus `plans/project-ultimate.md`. Windows 7 Ultimate information architecture for 2026. Every normal Windows job has to work with a mouse. Terminal stays a powerful app. It is not how you own the machine. The written “not a clone” line is ads, telemetry, and forced accounts — not permission to ship a Linux developer box.

## Doctrine (do not weaken)

1. Zero-terminal ownership. The terminal is an application, not a prerequisite for owning the computer.
2. Zero-hotkey-required. The mouse can do everything. Shortcuts are accelerators.
3. Windows muscle memory is an API. Start, taskbar, captions, Alt+Tab, Win+D/E/R/I/L/Arrows, Delete/F2/clipboard behave as a Windows user expects.
4. Visible before memorable. See the affordance before learning the chord.
5. Progressive disclosure. Settings → Display → Resolution is the normal path. Generated Hyprland config is Advanced.
6. Consequential operations have state. Current → proposed → progress → result → recovery. No surprise terminal scroll.
7. Recoverability is a flagship feature. Restore points, not Btrfs lectures.

Overlay rule: Desktop Mode must not rewrite `~/.config/omarchy/shell.json`. `shell.qml` computes effective `bar.id` / `bar.position`.

Service rule: QML never assembles shell strings for windowing or settings. UI calls typed verbs.

## What this product is not

Not a Windows clone. Not Aero. Not “Arch for Windows users.” Not a nicer Omarchy theme. Upstream Omarchy is a keyboard-first tiling distro on purpose. This fork keeps that plumbing and replaces the default product experience.

“Not a clone” refuses Windows ads, telemetry, and forced accounts. It does not license shipping a Linux developer box. Desktop Mode is Windows 7’s information architecture: Start, taskbar, files, Chrome, install apps, games, settings, printers, Wi-Fi — with a mouse. The terminal is an application. Power User Mode is where Linux tools stay first class.

Do not initially write a compositor, file manager, browser, package manager, audio stack, or installer. Use KDE as a component mine (Dolphin, Kate, Okular, Ark), not as the desktop. Study Zorin as the Windows-migration competitor, then go deeper than “layout that looks like Windows.”

## Branch strategy

Do not turn `quattro` into the experimental branch.

```text
upstream/quattro
      │
      ▼
quattro                    Clean tracking branch
      │
      ▼
ultimate/foundation        Typed WindowService + doctrine docs (exists)
      │
      ▼
ultimate/main              Product integration (create when a slice is actually accepted)
      │
      ├── ultimate/windowing     W0 / Phase 1  ← current work lives on cursor/desktop-mode-slice-00d6
      ├── ultimate/design-system
      ├── ultimate/taskbar
      ├── ultimate/start
      ├── ultimate/settings
      ├── ultimate/desktop
      ├── ultimate/files
      ├── ultimate/software
      └── ultimate/oobe
```

`cursor/desktop-mode-slice-00d6` is a local/cloud slice branch stacked on `ultimate/foundation`. It is not `ultimate/main`. Do not merge it because a harness printed green.

## Current position (2026-08-22)

Honest status, not a go. Reviewer lock: `4ea1dcf3` + `a5b945da` are kept; product is still REJECTED. Windowing is still not a go.

**Phase 0 (foundation)** is mostly in the repo: doctrine, acceptance manifest, mode profiles, design-token singleton, settings-service convention, shell tests, VM acceptance skeleton.

**Phase 1 (Windowing Gate W0)** is in progress on Hyprland 0.56.2 in the QEMU guest. It is not passed.

Start is a Desktop Mode surface now, not a developer launcher: idle Start hides Terminal/Vim (`developerToolsInStart` is false on the desktop profile), search still finds them, and shipped taskbar pins are Chrome and Files (`5942beaa`). A guest disk that only had foot and vim is a disk contents problem, not a reason to put the terminal on the Start menu. That is not Phase 6 Software Center and not a windowing go.

What exists:

- Desktop Mode profile (default) overlays the bottom `omarchy.ultimate-taskbar` without rewriting `shell.json`.
- `default/hypr/desktop-windows.lua` floats by default (`size = { 880, 560 }`), zeros tiling gaps, enables `resize_on_border`, and loads **hyprbars** from `/usr/lib/hyprland-plugins/hyprbars.so` (not a shell overlay, not hyprpm cache). Overlay plugin `omarchy.ultimate-window-chrome` is gone.
- `WindowService` talks Lua `hl.dsp.window.*` through `Hyprland.dispatch`, and minimize/restore through `hl.plugin.omarchy_minimize`. Monitor and client geometry for snap/remember come from `hyprctl -j monitors` / `hyprctl -j clients`, not Quickshell `mon.width` or stale `lastIpcObject`.
- Snap work area uses Hyprland 0.56 `reserved` as **left, top, right, bottom**. Live 1920×1080 reserved `[0,0,0,40]`. hyprbars draws above the hyprctl client box, so Desktop snap insets 32px: left `[0,32] 960×1008`, right `[960,32] 960×1008`. Pixel-checked close buttons sit at `y=9–22`.
- Default overlapping float: `[520,240] 880×560`. `restoreNormal` returned that rect after a right snap.
- Maximize `fullscreen: 1` `[2,34] 1916×1004` (title bar in the top of the work area; occupied bottom 1038 vs 1040).
- Minimize identity still holds — Desktop Mode now uses in-place `CWindow::setHidden` (`hidden: true` on the same workspace), not `special:minimized`. Restore returns the same address to the same workspace.
- SearchBox must not import `QtQuick.Controls` (that shadows `qs.Ui.TextField` with a stock white field).

What W0 still does not have (gate stays closed):

- Alt+Tab address-change as a number this lock will accept. `a4a046b3` stays; do not re-lock it as a go.
- Peek / jump lists / grouped previews as product, not a timer flyout.
- Quarter snap, maximize-button layout chooser, saved layouts.
- Multi-monitor, virtual desktops, parented dialogs, Steam / Wine / Electron / GTK / Qt matrix.
- hyprbars as a pacman package in the ISO mirror (runtime `.so` is now `/usr/lib/hyprland-plugins/hyprbars.so`, built by `omarchy-apply-hyprland-plugins`; `hyprland-plugin-hyprbars` still must not go in `install/omarchy-other.packages`).
- Tokyo Night as the locked visual, generic gear icons, Nautilus as Files, nvim as ordinary text, TTY first-boot, product ISO.
- A live path to install Chrome, games, or an arbitrary Windows app. That is Phase 6–7, not this windowing PR.

The leftover half-tile from the W0 probe is gone: new feet open as 880×560 floats, and unsnap restores the remembered rect. The GTK window is the visual proof; grim at 1080p while virtio preferred `640×480` was a lie.

**Phases 2–10** have not started as product. Tokens and `IconButton` exist as seeds. Start is not the masterpiece. There is no desktop icon surface, no Quick Settings composition, no Settings app, no Dolphin default, no Software Center, no Compatibility Center, no OOBE, no ISO.

Default theme, Nautilus, nvim-for-txt, TTY first boot that teaches Super+K, and the missing product ISO remain later slices. Do not paper over them in a windowing PR.

## Phases (vertical product capability)

Copied from the doctrine’s release architecture. Do not reorder to “make QML pretty.”

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifest, profiles, token layer, service convention, test/acceptance harness skeleton, `ultimate/foundation` branch.

Still open: clean `quattro` tracking vs `ultimate/main` integration branch; visual regression gallery; merge procedure written down.

### Phase 1 — Windowing Gate W0

Nothing else matters until this passes or we stop and change compositor.

Must demonstrate, reliably, not via IPC-only green:

- overlapping windows by default, remembered sizes/positions
- title-bar drag, edge/corner resize
- minimize / restore / maximize / unmaximize / close / activation / z-order
- taskbar activation and minimize/restore, grouped buttons, multiple windows per app
- Alt+Tab, Win+D, Win+Arrow halves then quarters, maximize-button snap chooser
- drag-to-top maximize, drag-away restore
- multi-monitor, virtual desktops, parented dialogs, fullscreen
- tray apps, XWayland, Steam, Wine, Chromium, Electron, GTK, Qt

Keep Hyprland only if that list is boring and maintainable. The forty-task harness rows 20–25 are necessary and not sufficient.

### Phase 2 — Design system

Running UI kit in `shell/Ui`, light/dark, compact/comfortable/touch later, no Nerd Font salad in consumer chrome, screenshot every state. Not mockups.

### Phase 3 — Desktop shell

Desktop surface, real taskbar (previews, jump lists, badges), masterpiece Start, tray, Quick Settings, notification center, calendar, lock. At the end of this phase it should already look like a different OS.

### Phase 4 — Settings

First-class app over typed services. Display, Sound, Network, Bluetooth, Input, Personalization, Apps, Update/Recovery first.

### Phase 5 — Files and defaults

Dolphin, This PC, desktop files, graphical text editor for ordinary `.txt`, MIME defaults, removable media, SMB.

### Phase 6 — Software

One Software surface; pacman/Flatpak/AUR/AppImage are implementation details with trust badges.

### Phase 7 — Windows compatibility

Compatibility Center, not “Wine.” Native / PWA / known-good / game / isolated / VM routing.

### Phase 8 — Administration

Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center.

### Phase 9 — OOBE and migration

Only when the product works. No package lists. No Super+K tutorial as first boot.

### Phase 10 — Brutal polish

Every hover, context menu, dialog, empty state, error, DPI, focus ring, reduced motion.

## What the next Cursor turn is allowed to do

The `4ea1dcf3` + `a5b945da` writeup is locked. Keep `eddd0b57` / `9d80ecd6` / `aaf601ca` / `5942beaa`. The last two commits stay (`5942beaa`, `a4a046b3`). Do not re-submit those SHAs for product review. Do not wait on another bench of the same HEAD. Do not treat `a4a046b3` as a locked Alt+Tab gate.

1. Treat W0 as still open. Do not merge PR #1 as a go. Do not rewrite the PR body to claim the OS.
2. Keep LTRB snap and typed `Hyprland.dispatch`. hyprbars is the Desktop Mode title bar, loaded from `/usr/lib/hyprland-plugins/`. Minimize is `hl.plugin.omarchy_minimize` (`setHidden`), not a special workspace. Relative ydotool is not a mouse proof. The GTK window is the visual proof; grim at 1080p is not.
3. New windows open as 880×560 floats. `restoreNormal` unsnaps to the remembered client rect. Snap insets 32px (bar height, not slop) so hyprbars stays on screen.
4. Do not start Phase 2–9 work (theme pack, Dolphin swap, Settings app, ISO, OOBE, Software Center, Compatibility Center) until W0 is decided — except a later slice that is itself one of the locked product gates after windowing is decided. Chrome, games, and “install any Windows app” are not a live path and are not this windowing PR.
5. Do not teach Super+K in Desktop Mode first boot. Do not make foot/vim first class because a guest disk lacked consumer `.desktop` files.
6. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Do not treat Alt+Tab address-change as a locked number. Generic gear icons, Tokyo Night, Nautilus, nvim, TTY first-boot, and the missing product ISO remain open.

## Acceptance

Release: a Windows-native tester completes all forty tasks in `WINDOWS_NATIVE_ACCEPTANCE.md` with no terminal and no web search.

Second test: an Omarchy/Arch power user can still terminal, pacman-equivalent, enable original bindings, tile, edit configs, script, install plugins.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0.
