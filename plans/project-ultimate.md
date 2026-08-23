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

Keep `4ea1dcf3` through `c1ae994f`. Those SHAs stay. Do not amend them. Do not squash them. Do not restore `--disable-features=WaylandWindowDecorations`.

The product call is still **REJECTED**. Windowing Gate W0 is **GO** on metal. Do not merge PR #1 as the OS.

What windowing actually is, live:

- hyprbars + omarchy-minimize from `/usr/lib/hyprland-plugins/`. Overlay captions gone. Minimize is `CWindow::setHidden`.
- Caption buttons name the bar's window (`0x{:x}`), not `closeActive` / `active`.
- Chromium/Firefox/Cursor/YouTube/Zoom PWAs use Wayland CSD and `hyprbars:no_bar`. Maximized Chromium `[1,1] 1918×1038`. Superbar charcoal, not Tokyo Night glass.
- Idle Start is Chrome and Files. foot and vim stay installed and searchable.

What did not move (not this slice):

- hyprbars is still not an ISO-mirror pacman package. The AUR name still must not go in `install/omarchy-other.packages`.
- Tokyo Night, generic gear icons, Nautilus, nvim, TTY first-boot, no product ISO.
- Chrome install-as-product, games, and “install any Windows app” are Phase 6–7.

Plans still win: `PRODUCT_DOCTRINE.md` plus `plans/project-ultimate.md`. Windows 7 Ultimate information architecture for 2026. Every normal Windows job has to work with a mouse. Terminal stays a powerful app. It is not how you own the machine.

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

Windowing Gate W0 is **GO** on the metal Hyprland 0.56.2 session. The product is still **REJECTED**. Do not merge PR #1 as the OS.

**Phase 0 (foundation)** is mostly in the repo: doctrine, acceptance manifest, mode profiles, design-token singleton, settings-service convention, shell tests, VM acceptance skeleton.

**Phase 1 (Windowing Gate W0)** passed on HDMI-A-1 1920×1080. Stack `4ea1dcf3` through `c1ae994f`. Next work is Phase 2.

What exists:

- Desktop Mode profile (default) overlays the bottom `omarchy.ultimate-taskbar` without rewriting `shell.json`.
- `default/hypr/desktop-windows.lua` floats by default (`size = { 880, 560 }`), zeros tiling gaps, enables `resize_on_border`, and loads **hyprbars** from `/usr/lib/hyprland-plugins/hyprbars.so`. Overlay plugin `omarchy.ultimate-window-chrome` is gone. Caption buttons exec `omarchy-shell window … 0x{:x}` for the bar owner.
- CSD browsers (class match, not the droppable `chromium-based-browser` tag) use `hyprbars:no_bar`. Live maximized Chromium `[1,1] 1918×1038`.
- `WindowService` talks Lua `hl.dsp.window.*` through `Hyprland.dispatch`, and minimize/restore through `hl.plugin.omarchy_minimize`.
- Snap work area uses Hyprland 0.56 `reserved` as **left, top, right, bottom**. Live 1920×1080 reserved `[0,0,0,40]`. SSD snap insets 32px; CSD snap insets 0.
- Minimize is in-place `CWindow::setHidden`, not `special:minimized`.

What W0 still does not pretend to be:

- hyprbars as a pacman package in the ISO mirror (`hyprland-plugin-hyprbars` still must not go in `install/omarchy-other.packages`).
- Peek thumbnails / jump lists (peek is a window list).
- Tokyo Night as the locked visual, generic gear icons, Nautilus as Files, nvim as ordinary text, TTY first-boot, product ISO.
- A live path to install Chrome, games, or an arbitrary Windows app. That is Phase 6–7.

**Phases 2–10** have not started as product. Tokens and `IconButton` exist as seeds. Start is not the masterpiece. There is no desktop icon surface, no Quick Settings composition, no Settings app, no Dolphin default, no Software Center, no Compatibility Center, no OOBE, no ISO.

Start is a Desktop Mode surface now, not a developer launcher: idle Start hides Terminal/Vim (`developerToolsInStart` is false on the desktop profile), search still finds them, and shipped taskbar pins are Chrome and Files (`5942beaa`).

Default theme, Nautilus, nvim-for-txt, TTY first boot that teaches Super+K, and the missing product ISO remain later slices. Do not paper over them in a windowing PR.

## Phases (vertical product capability)

Copied from the doctrine’s release architecture. Do not reorder to “make QML pretty.”

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifest, profiles, token layer, service convention, test/acceptance harness skeleton, `ultimate/foundation` branch.

Still open: clean `quattro` tracking vs `ultimate/main` integration branch; visual regression gallery; merge procedure written down.

### Phase 1 — Windowing Gate W0

Passed on metal (HDMI-A-1 1920×1080, stack through `c1ae994f`). Do not reopen it to redo LTRB / hyprbars / CSD. Steam/.exe, ISO, and theme are later phases, not a reason to un-go windowing.

Keep Hyprland. The forty-task harness rows 20–25 were necessary and not sufficient for the OS; they are sufficient for this windowing gate.

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

Keep `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not restore `--disable-features=WaylandWindowDecorations`.

1. Windowing W0 is GO. Do not merge PR #1 as the OS. Product is still REJECTED.
2. Next movable is Phase 2 (design system). Do not start ISO, gum, Tokyo Night seed, Nautilus, nvim-as-txt, or Steam/.exe in the same slice.
3. Keep LTRB snap, typed `Hyprland.dispatch`, `/usr/lib/hyprland-plugins` hyprbars, `omarchy-minimize` `setHidden`, class-based `hyprbars:no_bar`, addressed caption `0x{:x}`.
4. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.
5. Do not teach Super+K in Desktop Mode first boot. Do not make foot/vim first class.

## Acceptance

Release: a Windows-native tester completes all forty tasks in `WINDOWS_NATIVE_ACCEPTANCE.md` with no terminal and no web search.

Second test: an Omarchy/Arch power user can still terminal, pacman-equivalent, enable original bindings, tile, edit configs, script, install plugins.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0.
