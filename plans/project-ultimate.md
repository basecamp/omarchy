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

Keep `4ea1dcf3` + `a5b945da`. Those are the accepted repair. The product call is still **REJECTED**. Same open gates: no SSD, special-workspace minimize, 32px snap slop, no mouse proof, Tokyo Night, Nautilus, nvim, TTY first-boot, no ISO.

Do not re-run the full bench on that writeup. The next review is when a new turn actually moves one of those gates.

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

Honest status, not a go. Reviewer lock: `4ea1dcf3` + `a5b945da` are kept; product is still REJECTED.

**Phase 0 (foundation)** is mostly in the repo: doctrine, acceptance manifest, mode profiles, design-token singleton, settings-service convention, shell tests, VM acceptance skeleton.

**Phase 1 (Windowing Gate W0)** is in progress on Hyprland 0.56.2 in the QEMU guest. It is not passed.

What exists:

- Desktop Mode profile (default) overlays the bottom `omarchy.ultimate-taskbar` without rewriting `shell.json`.
- `default/hypr/desktop-windows.lua` floats by default and enables `resize_on_border`.
- `WindowService` talks Lua `hl.dsp.window.*` through `Hyprland.dispatch` (typed), not `bash -c` around a raw address.
- Snap work area uses Hyprland 0.56 `reserved` as **left, top, right, bottom**. The old live numbers `[40,0] 940×1080` were that axis bug, not a left exclusive zone.
- Live after the axis fix (1920×1080, reserved `[0,0,0,40]`): taskbar at `y=1040`; snap left `[0,0] 960×1054`, right `[960,0] 960×1054`; maximize `fullscreen: 1` `1916×1036`; minimize identity holds on `special:minimized`.
- First-cut taskbar, Start, Run, Settings destinations, Alt+Tab overlay, caption overlay plugin.

What W0 still does not have (gate stays closed):

- Conventional overlapping open size/position. Apps must not look tiled because two things opened, and they must not remain parked at a 50% snap from a probe.
- Real non-client chrome (minimize / maximize / close as Windows caption buttons, title-bar drag proven with the mouse, drag-to-top maximize, drag-away restore). Overlay captions on the client are a stand-in, not SSD.
- Peek / jump lists / grouped previews as product, not a timer flyout.
- Clickable Alt+Tab proven with the mouse (cards exist in QML).
- Quarter snap, maximize-button layout chooser, saved layouts.
- Multi-monitor, virtual desktops, parented dialogs, Steam / Wine / Electron / GTK / Qt matrix.
- Minimize that a Windows user would recognize. `special:minimized` is a compositor trick. If it becomes an unmaintainable special-workspace state machine, stop and replace the compositor before building more desktop.

The screenshot from 2026-08-22 11:43 is this state: Tokyo Night canvas, bottom taskbar, a Start that is still a search box plus `foot` / `vim`, Power User Mode footer, and **one floating window left at the right-hand snap from the W0 probe**. That right pane is not Hyprland tiling two clients. Desktop Mode’s window rule is `float = true`. It looks like a tile because snap parked it at half width with Hyprland’s active border. Leave it until W0 defines restore-to-normal bounds; do not “fix” it with a theme.

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

The `4ea1dcf3` + `a5b945da` writeup is locked. Do not re-submit it for product review. Do not wait on another bench of the same HEAD.

1. Treat W0 as still open. Do not merge PR #1 as a go. Do not rewrite the PR body to claim the OS.
2. Keep LTRB snap and typed `Hyprland.dispatch`. Overlay chrome and `special:minimized` are not a WM.
3. The right-hand half-window in the guest is leftover snap geometry. W0 should restore a normal floating rect on open/unsnap, not 50/50 as the default look.
4. Do not start Phase 2–9 work (theme pack, Dolphin swap, Settings app, ISO, OOBE) until W0 is decided — except a later slice that is itself one of the locked product gates (Tokyo Night, Nautilus, nvim, TTY first-boot, ISO) after windowing is decided.
5. Do not teach Super+K in Desktop Mode first boot.
6. Ask for a review only after a commit that actually moves: SSD, minimize, snap slop, mouse proof, or one of the remaining product gates.

## Acceptance

Release: a Windows-native tester completes all forty tasks in `WINDOWS_NATIVE_ACCEPTANCE.md` with no terminal and no web search.

Second test: an Omarchy/Arch power user can still terminal, pacman-equivalent, enable original bindings, tile, edit configs, script, install plugins.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0.
