# Project Ultimate — product plan

This is the working plan for the fork. It is not a theme plan. It is not a “move the bar to the bottom” plan. The locked identity is:

> **Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

Not: Windows-like Omarchy with AI tools.

Read this file together with:

- `PRODUCT_DOCTRINE.md` — eight rules (the original seven plus Agent-Native)
- `WINDOWS_NATIVE_ACCEPTANCE.md` — forty-task smoke test (necessary, not sufficient; six numbered rows automated, plus unnumbered harness proofs)
- `WINDOWS_7_ULTIMATE_PARITY.md` — job matrix
- `AGENT_NATIVE_ACCEPTANCE.md` — same-path agent matrix
- `docs/mode-profiles.md` — Desktop Mode vs Power User Mode as flags, one platform
- `docs/settings-service-api.md` — UI and agents → typed service → Omarchy/system tooling
- `docs/design-tokens.md` — one token pipeline for Superbar and hyprbars; no new private palettes
- `plans/desktop-mode-handoff.md` — live Hyprland windowing evidence and current next-work lock

If those documents and this plan disagree, the doctrine wins. If this plan and a PR description disagree, this plan wins. Do not take PR #1’s old “Windowing go/no-go — GO” as an OS go; that writeup was rejected.

## Reviewer lock (2026-08-22)

Keep `4ea1dcf3` through `c1ae994f`. Those SHAs stay. Do not amend them. Do not squash them. Do not restore `--disable-features=WaylandWindowDecorations`.

The product call is still **REJECTED**. Windowing Gate W0 is **architecture GO** on metal: Hyprland stays; conventional overlapping windows, hyprbars SSD, native minimize, LTRB snap, and addressed captions are feasible. W0 does **not** mean finished Windows 7 window management.

Do not merge `work` into `main` as the OS.

What windowing actually is, live (held from the metal session; not re-shot this docs turn):

- hyprbars + omarchy-minimize from `/usr/lib/hyprland-plugins/`. Overlay captions gone. Minimize is `CWindow::setHidden`.
- Caption buttons name the bar's window (`0x{:x}`), not `closeActive` / `active`.
- Chromium/Firefox/Cursor/YouTube/Zoom PWAs use Wayland CSD and `hyprbars:no_bar`. Maximized Chromium `[1,1] 1918×1038`. Superbar charcoal, not Tokyo Night glass.
- Idle Start is Chrome and Files. foot and vim stay installed and searchable.

What did not move (not this slice):

- hyprbars is still not an ISO-mirror pacman package. The AUR name still must not go in `install/omarchy-other.packages`.
- Tokyo Night, generic gear icons, Nautilus, nvim, TTY first-boot, no product ISO.
- Chrome install-as-product, games, and “install any Windows app” are later phases.

## Remaining W0 / product-windowing debt (architecture GO ≠ finished WM)

Recorded against the tree, not as live re-proof:

1. **Fourth caption button.** `desktop-windows.lua` (~183–211) `add_button`s close, maximize, snap-chooser (`▦`), then minimize. hyprbars draws right-to-left, so the visible order is **min / ▦ snapChooser / max / close**. Muscle-memory API is min / max / close. Snap belongs on maximize hover or drag-to-edge, not a fourth caption control. Address substitution is `formatWindowCmd` in `default/hypr/plugins/hyprbars/barDeco.cpp`, not in the Lua file.
2. **880×560 forced initial size** (`o.window(".*", { size = { 880, 560 } })`). In-session `_normalBounds` / `restoreNormal` and explicit `saveLayout` / `restoreLayout` to `~/.local/state/omarchy/ultimate/window-layout.json` exist. Missing is Windows 7 per-app reopen / cascade / per-monitor launch memory. Do not write “no remembered geometry.”
3. **CSD class lists are duplicated and not identical.** `hyprbars:no_bar` in `desktop-windows.lua` and `usesWaylandCsd` in `shell/services/WindowModel.js` both omit Nautilus (GTK CSD → expected two-row chrome; not live-reverified here). Zen is anchored in Lua (`^zen$` / `^zen-`) and compared after lowercase in JS; the regexes are not the same string.
4. **Plugin ABI durability.** `omarchy-apply-hyprland-plugins` compiles vendored hyprbars and omarchy-minimize into `/usr/lib/hyprland-plugins` at install (`install/config/hyprland-plugins.sh`). `omarchy-update` does **not** rebuild them. Hash mismatch in each `PLUGIN_INIT` throws (`hyprbars/main.cpp`, `omarchy-minimize/main.cpp`) — a Hyprland upgrade aborts **both** plugins. They must become versioned distro packages in the Hyprland release transaction. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Overlay chrome is gone. `WaylandWindowDecorations` stays enabled.

## Taskbar / Start / Settings honesty (known defects, not features)

- Superbar is a prototype, not the masterpiece. `TrayCluster.qml` hard-codes widgets; `barConfig` is unused. `Variants` already draws a bar per `Quickshell.screens` — missing is multi-monitor **policy**, not rendering. Chrome hexes include `#1b1b1b` `#333333` `#3a3a3a` `#4a4a4a` `#e8943a` `#9cbc0d` `#55ffffff`. hyprbars `bar_color` is `rgba(1a1a1acc)`.
- Start is a 440×560 glass launcher (search + pins + app list + Power User footer toggle), not Windows 7 Start.
- Settings (`omarchy.ultimate-settings`) is a stub: five buttons (Display, Sound, Network, Bluetooth, Power) that toggle existing panels.
- Peek is a title list. Right-click is **only** pin/unpin and "Close window." That close kills the entire group (`TaskButton.qml`). Peek × closes one.
- `feature()` is only consulted in `shell.qml` (`taskbar`/`topBar`) and `Start.qml` (`developerToolsInStart`).

## Doctrine (do not weaken)

1. Zero-terminal ownership. The terminal is an application, not a prerequisite for owning the computer.
2. Zero-hotkey-required. The mouse can do everything. Shortcuts are accelerators.
3. Windows muscle memory is an API. Start, Superbar, captions (min/max/close), Alt+Tab, Win+D/E/R/I/L/Arrows, Delete/F2/clipboard behave as a Windows user expects.
4. Visible before memorable. See the affordance before learning the chord.
5. Progressive disclosure. Settings → Display → Resolution is the normal path. Generated Hyprland config is Advanced.
6. Consequential operations have state. Current → proposed → progress → result → recovery. No surprise terminal scroll.
7. Recoverability is a flagship feature. Restore points, not Btrfs lectures.
8. Agent-native. Every meaningful human-desktop capability has a structured agent-callable equivalent. Same validators, transitions, errors, rollback, audit. No pixel scraping or random shell strings as the primary agent interface.

Overlay rule: Desktop Mode must not rewrite `~/.config/omarchy/shell.json`. `shell.qml` computes effective `bar.id` / `bar.position`.

Service rule: QML never assembles shell strings for windowing or settings. UI and agents call typed verbs.

Agent Center belongs in Desktop Mode as native as Start. `omarchy.agents` (usage/limits/cost/activity) stays visible until Agent Center exists. Preserve the Quattro plugin model under Windows-quality Superbar presentation.

## What this product is not

Not a Windows clone. Not Aero. Not “Arch for Windows users.” Not a nicer Omarchy theme. Not Omarchy-with-a-chat-panel. Upstream Omarchy is a keyboard-first tiling distro on purpose. This fork keeps that plumbing and replaces the default product experience.

“Not a clone” refuses Windows ads, telemetry, and forced accounts. It does not license shipping a Linux developer box. Desktop Mode is Windows 7 Ultimate’s information architecture: Start, Superbar, files, Chrome, install apps, games, settings, printers, Wi-Fi — with a mouse — and an agent fabric under those same jobs. The terminal is an application. Power User Mode is where Linux tools stay first class.

Do not initially write a compositor, file manager, browser, package manager, audio stack, or installer. Use KDE as a component mine (Dolphin, Kate, Okular, Ark), not as the desktop. Study Zorin as the Windows-migration competitor, then go deeper than “layout that looks like Windows.”

## Branch strategy

Hard rule: this fork has two branches only.

```text
upstream/quattro
      │
      ▼
main                       Clean tracking of upstream (default)
      │
      ▼
work                       All Ultimate product work
```

Do not create `cursor/*`, `ultimate/*`, or any other slice branches. Do not turn `main` into the experimental line. Phase work happens as commits on `work`. Do not merge `work` into `main` as the OS.

A full-repo backup of the pre-reconcile refs lives at `C:\dev\omarchy-vm\omarchy-all-refs-2026-08-22.bundle` on the Windows workstation, not in git. A reconciliation ledger should be produced from that bundle. This turn did not verify the bundle; do not claim proof of zero unique Jesse commits on deleted tips.

## Current position (2026-08-22)

Windowing Gate W0 is **architecture GO** on the metal Hyprland 0.56.2 session. The product is still **REJECTED**. Progress against the locked identity is roughly **15–20%**. Do not let a future agent declare victory after a shiny taskbar.

**Phase 0 (foundation)** is mostly in the repo: doctrine, acceptance manifests, mode profiles, design-token singleton, settings-service convention, shell tests, VM acceptance skeleton.

**Phase 1 (Windowing Gate W0)** architecture passed on HDMI-A-1 1920×1080. Stack `4ea1dcf3` through `c1ae994f`. Product windowing is not finished (see remaining debt above).

**Next locked work is Agent Fabric** (Phase 2 below): contract against WindowService, then restore `omarchy.agents` / plugin visibility on the Superbar. That is not a huge Phase 3 visual pass that assumes agents are optional later. Design-system token unification may proceed in parallel only as chrome pipeline work, not as new-surface sprawl.

What exists:

- Desktop Mode profile (default) overlays the bottom `omarchy.ultimate-taskbar` without rewriting `shell.json`.
- `default/hypr/desktop-windows.lua` floats by default (`size = { 880, 560 }`), zeros tiling gaps, enables `resize_on_border`, and loads **hyprbars** from `/usr/lib/hyprland-plugins/hyprbars.so`. Overlay plugin `omarchy.ultimate-window-chrome` is gone. `formatWindowCmd` in `barDeco.cpp` substitutes `0x{:x}`. Four caption buttons, visible min / ▦ snapChooser / max / close.
- CSD lists are duplicated in `desktop-windows.lua` and `WindowModel.js` (not identical; Nautilus omitted). Live maximized Chromium `[1,1] 1918×1038`.
- `WindowService` talks Lua `hl.dsp.window.*` through `Hyprland.dispatch`, and minimize/restore through `hl.plugin.omarchy_minimize`. First capability provider; not Agent Fabric.
- Snap work area uses Hyprland 0.56 `reserved` as **left, top, right, bottom**. Live 1920×1080 reserved `[0,0,0,40]`. SSD snap insets 32px; CSD snap insets 0.
- Minimize is in-place `CWindow::setHidden`, not `special:minimized`.
- Start is a Desktop Mode launcher: idle Start hides Terminal/Vim (`developerToolsInStart` is false on the desktop profile), search still finds them, shipped pins are Chrome and Files (`5942beaa`).

What W0 still does not pretend to be: three-button captions, Win7 per-app reopen/cascade/per-monitor launch memory, durable plugin packages (`omarchy-update` does not rebuild), peek thumbnails, jump lists, Agent Fabric, Agent Center, Settings, desktop icons, Software Center, Compatibility Center, OOBE, product ISO.

Profile flags for unimplemented surfaces are **false** (`desktopIcons`, `quickSettings`, `notificationCenter`). `snapLayouts` and `taskView` stay true because chooser and Task View overlay exist as prototypes.

**Phases 2–11** are not product-complete. Tokens are consumed (Start, Settings, TaskButton, switcher, snap); `themes/ultimate-light/` exists. Superbar/hyprbars chrome bypass is the leak, not “seed only.” Superbar/Start/Settings are prototypes or stubs. There is no desktop icon surface, no Quick Settings composition, no Settings app, no Dolphin default, no Software Center, no Compatibility Center, no OOBE, no ISO.

Default theme, Nautilus, nvim-for-txt, TTY first boot that teaches Super+K, and the missing product ISO remain later slices. Do not paper over them in a windowing PR.

## Audit vs tree (do not rubber-stamp)

Claims from the 2026-08-22 course-correction that this turn **verified in the tree**:

- Superbar hard-coded cluster; `omarchy.agents` absent from Desktop Mode chrome — true (`TrayCluster.qml` vs `config/omarchy/shell.json`).
- Start is a launcher — true (`Start.qml`).
- Settings is a stub — true (`ultimate-settings/Settings.qml` says so).
- Peek is titles — true. Group “Close window” closes all — true for the context menu; peek × closes one.
- Fourth caption button (visible min / ▦ / max / close) — true. `formatWindowCmd` lives in `barDeco.cpp` — true. 880×560 forced initial size — true. Compile-at-install plugins; `omarchy-update` does not rebuild; hash mismatch aborts both — true. `--disable-features=WaylandWindowDecorations` must not return — true (`config/chromium-flags.conf` enables the feature). `hyprland-plugin-hyprbars` is not in `install/omarchy-other.packages` — true.
- Six numbered forty-task rows automated (20–25) — true. The same harness also runs unnumbered proofs after the loop — true. Do not say only six tests exist.
- No Agent Fabric — true. WindowService exists — true. Settings-service “eventual AI” language is already gone; doctrine “eventually” is progressive disclosure only.

**Nuance / disagreement:**

- “Remembered geometry missing” is the wrong sentence. `_normalBounds` and `window-layout.json` exist. Missing is Win7 per-app reopen / cascade / per-monitor launch memory.
- `snapLayouts` / `taskView` are not unimplemented; they are prototypes. Flags stay true.
- `omarchy.notifications` exists as a toast/history daemon. That is not Notification Center. Flag is false without claiming notifications are absent.
- Superbar **does** load a tray (`Tray.qml`). “Hard-coded widget list” is the defect, not “no tray.”
- Nautilus two-row: expected from class-regex + GTK CSD; not live-reverified this run.
- ~15–20% is a product estimate, not a test metric.
- The refs bundle was not verified this run.

## Phases (vertical product capability)

Do not reorder to “make QML pretty.” Agent Fabric is the gate immediately after W0. Design-system token work may run alongside it; new Desktop Mode surfaces may not sprawl ahead of the fabric.

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifests, profiles, token layer, service convention, test/acceptance harness skeleton. That foundation is on `work`.

Still open: visual regression gallery.

### Phase 1 — Windowing Gate W0

Architecture GO on metal (HDMI-A-1 1920×1080, stack through `c1ae994f`). Keep Hyprland. Do not reopen LTRB / hyprbars / CSD / `setHidden` as if they were still dirty. Do not treat remaining caption/size/CSD/ABI debt as “windowing is the masterpiece.”

The forty-task harness rows 20–25 were necessary and not sufficient for the OS; they were sufficient as architecture evidence for this gate.

### Phase 2 — Agent Fabric (gate)

OS-level Agent Runtime and Capability Broker before UI sprawl. Provider adapters. Permissions/trust. Context broker. Persistent task/event model. Operation ledger. Recovery/undo. WindowService is the first provider; close its result shape to `{ changed, error }`. Restore `omarchy.agents` (and the plugin model) on the Superbar until Agent Center exists. The agent UI can wait; this architecture cannot.

### Phase 3 — Design system

Running UI kit in `shell/Ui`, light/dark, compact/comfortable/touch later, no Nerd Font salad in consumer chrome, screenshot every state. One token/theme pipeline must drive Superbar **and** hyprbars (light theme must propagate). Not mockups. Not an excuse to invent new product surfaces.

### Phase 4 — Desktop shell

Desktop surface, real Superbar (plugin-hosted widgets, previews, jump lists, badges), masterpiece Start, tray, Quick Settings, notification center, calendar, lock. **Agent Center as native as Start** (tasks, active agents, pending actions, automations, history, context; usage widget is one section). At the end of this phase it should already look like a different OS. Do not start this sprawl by assuming agents are later.

### Phase 5 — Settings

First-class app over typed services. Display, Sound, Network, Bluetooth, Input, Personalization, Apps, Update/Recovery first. Same verbs as Agent Fabric.

### Phase 6 — Files and defaults

Dolphin, This PC, desktop files, graphical text editor for ordinary `.txt`, MIME defaults, removable media, SMB.

### Phase 7 — Software

One Software surface; pacman/Flatpak/AUR/AppImage are implementation details with trust badges.

### Phase 8 — Windows compatibility

Compatibility Center, not “Wine.” Native / PWA / known-good / game / isolated / VM routing.

### Phase 9 — Administration

Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center.

### Phase 10 — OOBE and migration

Only when the product works. No package lists. No Super+K tutorial as first boot.

### Phase 11 — Brutal polish

Every hover, context menu, dialog, empty state, error, DPI, focus ring, reduced motion.

## What the next Cursor turn is allowed to do

Keep `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not restore `--disable-features=WaylandWindowDecorations`.

1. Windowing W0 is architecture GO. Do not merge PR #1 as the OS. Product is still REJECTED.
2. Next movable is **Agent Fabric contract + Superbar plugin/`omarchy.agents` visibility**. Do not start a huge Phase 3/4 visual pass. Do not start ISO, gum, Tokyo Night seed, Nautilus, nvim-as-txt, or Steam/.exe in the same slice. Do not implement Agent Center UI, Superbar peek bitmaps, caption-button redesign, or plugin packaging in a docs pass.
3. Keep LTRB snap, typed `Hyprland.dispatch`, `/usr/lib/hyprland-plugins` hyprbars, `omarchy-minimize` `setHidden`, class-based `hyprbars:no_bar`, addressed caption `0x{:x}`.
4. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.
5. Do not teach Super+K in Desktop Mode first boot. Do not make foot/vim first class.
6. Stay on `work`. Never create `cursor/*`. Never push `main`. Never force-push.

## Acceptance

Release requires all three:

1. Forty-task smoke test (`WINDOWS_NATIVE_ACCEPTANCE.md`) — a Windows-native tester completes all forty with no terminal and no web search.
2. Job parity (`WINDOWS_7_ULTIMATE_PARITY.md`).
3. Agent-native matrix (`AGENT_NATIVE_ACCEPTANCE.md`).

Second test: an Omarchy/Arch power user can still terminal, pacman-equivalent, enable original bindings, tile, edit configs, script, install plugins.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0 and does not pass the OS.
