# Project Ultimate — product plan

This is the working plan for the fork. It is not a theme plan. It is not a “move the bar to the bottom” plan. The locked identity is:

> **Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

Not: Windows-like Omarchy with AI tools.

Resume from `HANDOFF_NEW_BOX_2026-08-23.md` (immutable). That file wins on next-work order if this plan still says fabric-next.

Read this file together with:

- `HANDOFF_NEW_BOX_2026-08-23.md` — current lock (P0s, Start click-through, screensaver, branding)
- `PRODUCT_DOCTRINE.md` — eight rules (the original seven plus Agent-Native)
- `WINDOWS_NATIVE_ACCEPTANCE.md` — forty-task smoke test (necessary, not sufficient; six numbered rows automated, plus unnumbered harness proofs)
- `WINDOWS_7_ULTIMATE_PARITY.md` — job matrix
- `AGENT_NATIVE_ACCEPTANCE.md` — same-path agent matrix
- `docs/mode-profiles.md` — Desktop Mode vs Power User Mode as flags, one platform
- `docs/settings-service-api.md` — UI and agents → typed service → Omarchy/system tooling
- `docs/design-tokens.md` — one token pipeline for Superbar and hyprbars; no new private palettes
- `plans/desktop-mode-handoff.md` — live Hyprland windowing evidence; current next-work lock is the HANDOFF file

If those documents and this plan disagree, the doctrine wins. If this plan and a PR description disagree, this plan wins. Do not take PR #1’s old “Windowing go/no-go — GO” as an OS go; that writeup was rejected.

## Reviewer lock (2026-08-22, held)

Keep `4ea1dcf3` through `c1ae994f`. Those SHAs stay. Do not amend them. Do not squash them. Do not restore `--disable-features=WaylandWindowDecorations`.

The product call is still **REJECTED**. Do not merge `work` into `main` as the OS.

## W0 product-windowing (2026-08-23 metal)

Windowing Gate W0 is **architecture GO** (Hyprland stays) and now **product-windowing GO** on HDMI-A-1 1920×1080. That is not an OS go.

Live this session (`windows-native-test.sh` exit 0 including numbered 20–25 and unnumbered proofs; `hyprbars-pointer-proof.py` exit 0 including maximize-hover snap chooser and unfocused addressed close):

- Three caption buttons, visible min / max / close. Snap is maximize hover (`hover_action` → `snapChooser 0x{:x}`), drag-to-edge, and Super+Z. No `▦` button.
- CSD classes from `default/ultimate/csd-clients.json` (Lua `hyprbars:no_bar` + WindowModel). Chromium one CSD row; Files/Nautilus GTK CSD only (no hyprbars two-row). `WaylandWindowDecorations` still on.
- Per-app reopen memory in `~/.local/state/omarchy/ultimate/window-placements.json` via WindowService. 880×560 remains the Hyprland fallback only. Cascade when there is no memory; clamp to the window's monitor; do not reopen a snap as the saved size.
- `omarchy-update` rebuilds hyprbars + omarchy-minimize after `omarchy-update-system-pkgs` (`omarchy-apply-hyprland-plugins`). A failed rebuild fails the update. Still **not** AUR `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Versioned distro packages remain the durable end state.
- Superbar group menu: **Close group** when `windows.length > 1`, else **Close window**. Peek × still one window.

What did not move (not this slice):

- hyprbars is still not an ISO-mirror pacman package.
- Tokyo Night seed, nvim-as-txt, TTY first-boot, no product ISO.
- Chrome install-as-product, games, and “install any Windows app” are later phases.
- Peek thumbnails, jump lists, Agent Center UI, Settings app.

## Remaining W0 / product-windowing debt

The four product-windowing debts from 2026-08-22 are **closed** on metal. Left for later packaging, not as an excuse to reopen W0:

- Plugins compile in the update transaction; they are still not versioned distro packages in the Hyprland release. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Overlay chrome is gone. `WaylandWindowDecorations` stays enabled.

## Taskbar / Start / Settings honesty (known defects, not features)

- Superbar is a prototype, not the masterpiece. Notification-area cluster is driven from `barConfig.layout.right` + `BarWidgetRegistry` (`TrayCluster.qml`). Desktop Mode overlay includes `omarchy.agents` without rewriting `shell.json`. Chrome hexes include `#1b1b1b` `#333333` `#3a3a3a` `#4a4a4a` `#e8943a` `#9cbc0d` `#55ffffff`. hyprbars `bar_color` is `rgba(1a1a1acc)`. `Variants` already draws a bar per `Quickshell.screens` — missing is multi-monitor **policy**, not rendering.
- Start is a 440×560 glass launcher (search + pins + app list + Power User footer toggle), not Windows 7 Start. Outside-click and Start-orb re-toggle landed in `e3bf9385` (full-screen swallow). Remaining: Windows click-through via a shared transient coordinator (`HANDOFF_NEW_BOX_2026-08-23.md`).
- Settings (`omarchy.ultimate-settings`) is a stub: five buttons (Display, Sound, Network, Bluetooth, Power) that toggle existing panels.
- Peek is a title list. Right-click is pin/unpin and **Close group** / **Close window** (label follows `windows.length`). Peek × closes one.
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

## Branch reconciliation (locked 2026-08-22)

Do not re-audit this from memory. The ledger is **outside the product repo** — do not commit the bundle or copy ~240 MB into git:

- Bundle: `C:\dev\omarchy-vm\omarchy-all-refs-2026-08-22.bundle` (251209890 bytes, 145 refs, `git bundle verify` okay)
- Ledger: `C:\dev\omarchy-vm\branch-reconciliation-ledger-2026-08-22.md`

**Heads PASS.** GitHub / Windows / box `refs/heads/*` are only `main` and `work`. `main` == `2c247e39` == live `basecamp/omarchy` **`quattro`** (not `master`; `master` is `f4378f0d`). At ledger time `work` was `c4c6ce29`, **35 ahead / 0 behind** `main`, merge-base is `main`. Docs commits after the ledger (`e03f777e`, then `25b6e6de` and later) moved `work` — do not reset. All named Ultimate SHAs and the 16 locked W0 SHAs are ancestors of `work`. `.cursor/environment.json` and `.cursor/install.sh` are on `work`.

**Claim 6 content PASS.** 73 deleted origin/local tip names vs `work`: 240 unique commits (almost all upstream DHH/Omabot), 386 unique blobs (upstream, not Jesse). **Jesse unique blobs: 0.** No Jesse-looking file is present on a deleted tip and missing from the `work` tree.

**Claim 6 strict unique-commit SHA FAIL — one exception.** `30aac92fccb2a03118e4c7bb461cdd54d7b29050` “Merge branch 'basecamp:quattro' into cursor/cloud-agent-dev-environment-a448” by jnadeau207-collab. Parents `28a8bdfb` and `2c247e39` are **both** already ancestors of `work`. Unique blobs on that tip: 0. `git diff --diff-filter=A work 30aac92f` is empty. No file content lost; only that merge SHA is absent from `work` ancestry. 72/73 deleted names have zero unique Jesse commit or blob.

Do **not** claim mathematical zero unique Jesse *commits*. Claim zero unique Jesse *content*, plus one orphan merge SHA with an empty tree diff.

**Caveats (not branches):** 65 version tags remain; `refs/pull/1/head` and `refs/pull/2/head` remain. If someone reads “GitHub has no refs except main and work,” that reading fails. The two-branch **head** claim passes.

## Current position (2026-08-23)

Windowing Gate W0 is **architecture GO** and **agent-reported product-windowing GO** on the metal Hyprland 0.56.2 session (HDMI-A-1 1920×1080). Independent review has not certified `687d022b` from a clean checkout. The product is still **REJECTED**. Desktop shell acceptance is **FAIL** until Start click-through is proven. Progress against the locked identity is roughly **20%**. Do not let a future agent declare victory after a green harness.

**Next work is not more fabric and not Agent Center UI.** Order is `HANDOFF_NEW_BOX_2026-08-23.md` §In flight: Download Video P0, FIDO2 P0, Start click-through, screensaver/branding. `e3bf9385` already closed ordinary Start dismiss.

**Phase 0 (foundation)** is mostly in the repo: doctrine, acceptance manifests, mode profiles, design-token singleton, settings-service convention, shell tests, VM acceptance skeleton.

**Phase 1 (Windowing Gate W0)** product-windowing passed on metal. Stack `4ea1dcf3` through `c1ae994f` stays. Do not reopen LTRB / hyprbars / CSD / `setHidden` / three-button captions / Files chrome / reopen memory as if they were still dirty.

**Phase 2 (Agent Fabric) minimum pass bar is closed** against WindowService: `{ changed, error }`, capability broker, local-session permissions, operation ledger, window undo via `restoreNormal` / `restoreLayout`, Superbar cluster from the bar-widget registry with `omarchy.agents` visible. Display/Audio/Network are still panels. Agent Center UI, full capability graph, sandboxed runtime, and persistent tasks are **not** this pass.

What exists:

- Desktop Mode profile (default) overlays the bottom `omarchy.ultimate-taskbar` without rewriting `shell.json`. Overlay `bar.layout.right` includes `omarchy.agents`. Live disk `~/.config/omarchy/shell.json` stayed heritage (`bar.id` unset, `position: top`).
- `default/hypr/desktop-windows.lua` floats by default (`size = { 880, 560 }` fallback only), zeros tiling gaps, enables `resize_on_border`, and loads **hyprbars** from `/usr/lib/hyprland-plugins/hyprbars.so`. Overlay plugin `omarchy.ultimate-window-chrome` is gone. `formatWindowCmd` in `barDeco.cpp` substitutes `0x{:x}`. Three caption buttons, visible min / max / close. Maximize `hover_action` summons `omarchy.ultimate-snap-chooser`.
- CSD from `default/ultimate/csd-clients.json` (Chromium family, Firefox, anchored Zen, YouTube/Zoom PWA, Cursor, Nautilus). Live grim: Chromium one CSD row; Files no hyprbars row. zenity is not Zen.
- `WindowService` talks Lua `hl.dsp.window.*` through `Hyprland.dispatch`, and minimize/restore through `hl.plugin.omarchy_minimize`. Writers return `{ changed, error }` and record through `CapabilityBroker`. IPC serializes that object (`ping` stays `"ok"`).
- Snap work area uses Hyprland 0.56 `reserved` as **left, top, right, bottom**. Live 1920×1080 reserved `[0,0,0,40]`. SSD snap insets 32px; CSD snap insets 0.
- Minimize is in-place `CWindow::setHidden`, not `special:minimized`.
- Start is a Desktop Mode launcher: idle Start hides Terminal/Vim (`developerToolsInStart` is false on the desktop profile), search still finds them, shipped pins are Chrome and Files (`5942beaa`).

What this still does not pretend to be: peek thumbnails, jump lists, Agent Center, Settings app, desktop icons, Software Center, Compatibility Center, OOBE, product ISO, versioned hyprbars packages.

Profile flags for unimplemented surfaces are **false** (`desktopIcons`, `quickSettings`, `notificationCenter`). `snapLayouts` and `taskView` stay true because chooser and Task View overlay exist as prototypes.

**Phases 3–11** are not product-complete. Tokens are consumed (Start, Settings, TaskButton, switcher, snap); `themes/ultimate-light/` exists. Superbar/hyprbars chrome bypass is the leak, not “seed only.” Superbar/Start/Settings are prototypes or stubs. There is no desktop icon surface, no Quick Settings composition, no Settings app, no Dolphin default, no Software Center, no Compatibility Center, no OOBE, no ISO.

Default theme, nvim-for-txt, TTY first boot that teaches Super+K, and the missing product ISO remain later slices. Do not paper over them in a windowing PR.

## Audit vs tree (do not rubber-stamp)

Claims from the 2026-08-22 course-correction that this turn **verified in the tree and on metal**:

- Superbar cluster from bar-widget registry; Desktop Mode overlay includes `omarchy.agents`; disk `shell.json` not rewritten — true (`overlayShellConfig`, `TrayCluster.qml`, live disk `bar.id` unset / `position: top`).
- Start is a launcher — true (`Start.qml`).
- Settings is a stub — true (`ultimate-settings/Settings.qml` says so).
- Peek is titles — true. Group close label is **Close group** / **Close window**; the action still closes every window in the group; peek × closes one.
- Three caption buttons (visible min / max / close); maximize hover summons snap chooser; `formatWindowCmd` lives in `barDeco.cpp` — true. 880×560 is fallback only; `window-placements.json` remembers per-app floats — true live (foot 1000×620 at `[120,80]` reopened). `omarchy-update` rebuilds plugins after system packages — true. `--disable-features=WaylandWindowDecorations` must not return — true. `hyprland-plugin-hyprbars` is not in `install/omarchy-other.packages` — true.
- Six numbered forty-task rows automated (20–25) — true. The same harness also runs unnumbered proofs after the loop — true, live exit 0 this session. Pointer proof includes maximize hover and unfocused addressed close — true.
- WindowService is the first fabric provider with `{ changed, error }`, broker, ledger, and invertible restore tokens — true. Full OS capability graph, sandboxed runtime, and Agent Center UI are still missing.

**Nuance / disagreement:**

- `snapLayouts` / `taskView` are not unimplemented; they are prototypes. Flags stay true.
- `omarchy.notifications` exists as a toast/history daemon. That is not Notification Center. Flag is false without claiming notifications are absent.
- Superbar **does** load a tray (`Tray.qml`) and now loads the registry cluster including `omarchy.agents`.
- Files two-row chrome is **gone** on metal (GTK CSD only).
- ~20% is a product estimate, not a test metric.
- Branch/bundle uniqueness: see the locked ledger section above. Zero unique Jesse **content**; one orphan merge SHA (`30aac92f`) with an empty diff. Do not restate “unverified.”

## Phases (vertical product capability)

Do not reorder to “make QML pretty.” Phase 2 window-fabric minimum is closed. Remaining fabric depth is later. **Now:** P0 security, then Start click-through, then screensaver/branding (`HANDOFF_NEW_BOX_2026-08-23.md`). New Desktop Mode surfaces may not sprawl ahead of that.

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifests, profiles, token layer, service convention, test/acceptance harness skeleton. That foundation is on `work`.

Still open: visual regression gallery.

### Phase 1 — Windowing Gate W0

Architecture GO and product-windowing GO on metal (HDMI-A-1 1920×1080, stack through `c1ae994f`). Keep Hyprland. Do not reopen LTRB / hyprbars / CSD / `setHidden` / three-button captions / Files chrome / reopen memory / update-transaction plugin rebuild as if they were still dirty.

The forty-task harness rows 20–25 were necessary and not sufficient for the OS; with the unnumbered proofs they were sufficient as architecture **and** product-windowing evidence for this gate.

### Phase 2 — Agent Fabric (gate)

Minimum pass bar (2026-08-23): WindowService `{ changed, error }`, capability broker, local-session permit (ui/ipc/agent/undo), ledger `~/.local/state/omarchy/ultimate/capability-ledger.json`, window undo via recorded `restoreNormal` / `restoreLayout`, Superbar cluster from `BarWidgetRegistry` with `omarchy.agents` visible. Same WindowService verbs from QML and `omarchy-shell window`.

Still missing on purpose: full parity-graph catalog (row 1), persistent Agent Center tasks (8), rich context broker (9), sandboxed Agent Runtime (11). Display/Audio/Network stay panels until Phase 5. Agent Center UI is Phase 4.

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

1. Windowing W0 is architecture GO and product-windowing GO. Do not merge PR #1 as the OS. Product is still REJECTED.
2. Phase 2 minimum pass bar is closed. Do not start Agent Center UI, Superbar peek bitmaps, or a huge Phase 3/4 visual pass as if fabric depth were done. Next movable is later fabric depth (catalog, context, sandboxed runtime) **or** Phase 3 token unification for Superbar/hyprbars — not ISO, gum, Tokyo Night seed, nvim-as-txt, or Steam/.exe in the same slice.
3. Keep LTRB snap, typed `Hyprland.dispatch`, `/usr/lib/hyprland-plugins` hyprbars, `omarchy-minimize` `setHidden`, JSON CSD `hyprbars:no_bar`, addressed caption `0x{:x}`, three-button SSD, maximize hover snap.
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
