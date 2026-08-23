# Desktop Mode Slice — Local Session Handoff

Live Hyprland evidence for Desktop Mode windowing, plus the current next-work lock. Cloud pods cannot prove this: `/dev/kvm` without a faithful guest is not a session.

Do not treat this file as advisory. Historical tranches below are evidence. **Current truth is this section, not §0–§0i (those still say “W0 is still open” because they were written before architecture GO).**

## Current lock (2026-08-22 course-correction)

**Identity:** Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability. **Not** Windows-like Omarchy with AI tools.

**Branches:** default `main` (upstream tracking only; `2c247e39` == basecamp `quattro`). All Ultimate work is `work`. Do not create `cursor/*` or other slice branches. Do not merge `work` into `main` as the OS. Product is still **REJECTED**. Reconciliation ledger (outside git): `C:\dev\omarchy-vm\branch-reconciliation-ledger-2026-08-22.md` — two heads PASS; zero unique Jesse **content**; one orphan merge SHA `30aac92f` with empty diff. Ledger-time `work` was `c4c6ce29`; later docs moved HEAD — do not reset.

**W0:** architecture **GO** on metal (Hyprland stays). That is not finished Windows 7 window management. Remaining product-windowing debt: fourth caption button (visible min / ▦ snapChooser / max / close; `formatWindowCmd` is in `barDeco.cpp`); 880×560 forced initial size (`_normalBounds` and `~/.local/state/omarchy/ultimate/window-layout.json` exist — missing is Win7 per-app reopen / cascade / per-monitor launch memory, not “no remembered geometry”); CSD lists duplicated in `desktop-windows.lua` + `WindowModel.js`, not identical, Nautilus omitted; plugins compile via `omarchy-apply-hyprland-plugins` into `/usr/lib/hyprland-plugins/`, `omarchy-update` does not rebuild, hash mismatch aborts hyprbars **and** minimize. Overlay chrome is gone. Do not restore `--disable-features=WaylandWindowDecorations`. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.

**Honesty:** Superbar is a prototype (`TrayCluster` hard-coded; `barConfig` unused; chrome hexes include `#3a3a3a` `#4a4a4a`; `Variants` already maps per screen — policy missing, not rendering). Start is a 440×560 glass launcher with Power User on the footer. Settings is a five-button stub. Peek is a title list; right-click is only pin/unpin/close; “Close window” closes the group. Tokens are consumed; Superbar/hyprbars chrome bypass is the leak. Progress ~15–20% of the OS vision.

**Next locked work (do this, not a huge Phase 3/4 visual pass):**

1. Agent Fabric contract on top of WindowService (runtime, capability broker, permissions, ledger, undo). Agent UI can wait; architecture cannot.
2. Restore `omarchy.agents` and Quattro plugin visibility in Desktop Mode Superbar. `TrayCluster.qml` hard-codes widgets and drops the heritage `omarchy.agents` entry. Agent Center belongs in Desktop Mode as native as Start; until it exists the usage widget stays visible.

KEEP `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not squash them.

Read `PRODUCT_DOCTRINE.md` (eight rules), `plans/project-ultimate.md`, `WINDOWS_NATIVE_ACCEPTANCE.md` (smoke test; six numbered rows automated, plus unnumbered harness proofs), `WINDOWS_7_ULTIMATE_PARITY.md`, `AGENT_NATIVE_ACCEPTANCE.md`.

## Historical W0 tranches

The following §0–§0j blocks are dated session locks. Do not execute “W0 is still open” or “next phase is Phase 2 design system” from them.

## 0. Reviewer lock (2026-08-22) — historical, pre-GO

Keep `4ea1dcf3` and `a5b945da`. Those are the accepted repair. Do not amend them. Do not squash them. Do not redo the LTRB / `Hyprland.dispatch` / Start-label / click-handler work as if it were still dirty.

The product call is still **REJECTED**. Windowing Gate W0 is still open. The same open gates, unchanged:

- no compositor SSD (overlay captions are not SSD)
- minimize is still `special:minimized`
- snap still allowed 32px of slop (live 1054 vs 1040)
- no mouse proof (title-bar drag, Alt+Tab clicks)
- Tokyo Night
- Nautilus
- nvim as ordinary text
- TTY first-boot
- no product ISO

Do not re-run the full review bench on that writeup. Do not ask for another product review of HEAD `a5b945da`. The next review is only when a new turn actually moves one of those gates.

## 0b. W0 Tranche B (2026-08-22) — gates that moved, gates that did not

This is not a product go. Windowing Gate W0 is still open. Two locked gates moved on the live guest; the others did not.

Moved:

- Snap slop / 1054 vs 1040. Snap geometry is compositor `hyprctl -j monitors` only (LTRB reserved). Live reserved `[0,0,0,40]`. After insetting 32px for hyprbars (which draws above the hyprctl client box), snap is left `[0,32] 960×1008`, right `[960,32] 960×1008`. Title-bar close buttons are on-screen at `y=9–22`. Default float is `880×560` at `[520,240]`. `restoreNormal` returned that same rect after a right snap.
- Overlay-as-SSD. `omarchy.ultimate-window-chrome` is deleted. hyprbars is loaded via hyprpm (`hyprpm enable hyprbars`; `.so` at `/var/cache/hyprpm/omarchy/hyprland-plugins/hyprbars.so`). Overlay layer count 0. Caption buttons are compositor decorations.

Still open:

- Minimize is still `special:minimized`.
- Mouse proof. Cursor can sit on the measured close button; ydotool / QEMU HMP / VNC clicks from this host did not actuate it. Do not call title-bar drag a go.
- Tokyo Night, Nautilus, nvim, TTY first-boot, no product ISO.

Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages` (pacman-only; package is not in the repos). Desktop Mode loads hyprpm’s `.so` and `hyprpm reload -n` on `hyprland.start`.

Do not re-bench `4ea1dcf3` + `a5b945da`. The next review is this tranche’s commits plus the live numbers above — and only as a gate update, not as an OS go.

## 0c. W0 Tranche C lock (2026-08-22) — mouse gate only; W0 is still open

Keep `eddd0b57` and `9d80ecd6`. Do not re-bench `4ea1dcf3` + `a5b945da`. Do not re-open `eddd0b57`. Windowing is still not a go. Bench stays idle.

HEAD is still `eddd0b57`. The dirty tree is a harness and cycle cleanup on top of Tranche B, not a new product SHA. Do not treat uncommitted files as a windowing go or as a new review SHA.

Tranche C is the mouse gate only. What actually moved:

- hyprbars is hittable with an absolute USB-tablet-class pointer. Relative ydotool was the wrong seat (`cursorpos` follows, buttons do not). That is compositor chrome, not “hyprbars ignores clicks.”
- Close at `1384,224` then `1516,309` unmapped the foot. Overlay chrome is still gone (layer count 0).
- Title-bar drag `[520,240]` → `[652,325]` (Δ132×85, over the 8px slop).
- 32px is bar-height inset, not snap slop.

What did not move:

- Alt+Tab address-change is not a held number. One painted-card click hid the overlay; that is not activate-the-other-foot. Do not treat the helper’s address-change assert as proven on this multi-pointer VM seat.
- Minimize is still `special:minimized`.
- hyprbars is still a hyprpm cache `.so`.
- Theme, Nautilus, nvim, TTY, ISO did not move.

The uncommitted helper is honest: missing `/dev/uinput` fails, it does not skip. `windows-native-test.sh` runs it. Alt+Tab in the harness is summon + screenshot, not `commitCycle` as the mouse proof. `cancelCycle` on overlay hide is correct. Cards are 120×120.

Next gate that can actually move is native minimize, or hyprbars as a real package. Stay idle until one of those lands.

## 0d. W0 Tranche D (2026-08-22) — native minimize; W0 is still open

Worker slice after the Tranche C lock. Keep `eddd0b57` and `9d80ecd6`. Do not re-bench `4ea1dcf3` + `a5b945da`. Windowing is still not a go.

Moved:

- Minimize is no longer a `special:minimized` park. `omarchy-minimize` calls `CWindow::setHidden` on the same workspace. Live: four feet `hidden: true`, `workspace.id == 1`. Grim of the empty desktop is wallpaper `(17,17,17)` at the old client box; restore of `0x555bb2579650` returns `hidden: false` on workspace `1` with close-button red `(227,158,152)`.
- `WindowService.minimize` / `restore` dispatch `hl.plugin.omarchy_minimize.*`. Caption minimize still goes through `omarchy-shell window`.

Did not move:

- hyprbars is still a hyprpm cache `.so`.
- Alt+Tab address-change is still not a held number.
- Theme, Nautilus, nvim, TTY, ISO did not move.
- The plugin `.so` is ABI-pinned and built on the Hyprland machine (`/usr/lib/hyprland-plugins/omarchy-minimize.so`). That is not a pacman package in the ISO mirror.

## 0e. W0 Tranche E (2026-08-22) — hyprbars off hyprpm; W0 is still open

Worker slice after the Tranche D lock. Keep `eddd0b57` and `9d80ecd6`. Do not re-bench `4ea1dcf3` + `a5b945da`. Windowing is still not a go.

Moved:

- hyprbars is no longer a hyprpm cache `.so`. `omarchy-apply-hyprland-plugins` builds vendored hyprbars `v0.56.0` and `omarchy-minimize` into `/usr/lib/hyprland-plugins/`. Live `/proc/Hyprland/maps`: `/usr/lib/hyprland-plugins/hyprbars.so` and `/usr/lib/hyprland-plugins/omarchy-minimize.so`. No `/var/cache/hyprpm/` mapping. Overlay chrome still gone. Close pixel `(227,158,152)` on a `[520,240] 880×560` foot.
- `desktop-windows.lua` does not call `hyprpm reload` and does not load `/var/cache/hyprpm/`.

Did not move:

- Not a pacman package in the ISO mirror. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.
- Alt+Tab address-change is still not a held number.
- Theme, Nautilus, nvim, TTY, ISO did not move.

## 0f. Desktop Mode Start is consumer-first (2026-08-22)

W0 is still open. This is not Software Center and not a windowing go.

Idle Start was listing AppSearch sort wrappers as apps, so the menu led with **foot** and **vim** and generic gear icons. Start now unwraps `.entry`, hides developer tools unless the user is searching (`developerToolsInStart` is false on the desktop profile), and loads shipped pins Chrome and Files when the user has no `taskbar-pins.json`. Search still finds foot/vim. Landed as `5942beaa`.

## 0g. W0 Tranche F (2026-08-22) — Alt+Tab address-change; W0 is still open

Keep `aaf601ca` and `5942beaa`. Do not re-open `eddd0b57`. Windowing is still not a go.

Moved:

- `omarchy-shell window commitCycle` changed the active foot `0x56298316a300` → `0x56298351ec30`. Overlay `omarchy-task-switcher` unmapped.
- Absolute pointer click on the highlighted card (`896,540`) changed active `0x56298351ec30` → `0x56298316a300`. Overlay unmapped. Drag `[520,240]` → `[652,325]`. Close at `1516,309` unmapped.

Root cause: the switcher took `WlrKeyboardFocus.OnDemand`, so hide restored the previous window. `restore()` did not focus a visible client. Hide invoked `close()` which cancelled the cycle before commit could read `cycleList`. Fix: `WindowService.activate` (restore-if-hidden, then `hl.dsp.focus`); capture address before hide; `WlrKeyboardFocus.None`; card pick activates after overlay hide.

Did not move: hyprbars as a pacman package; peek/jump lists; quarter snap; multi-monitor; Tokyo Night, Nautilus, nvim, TTY, ISO.

`a4a046b3` stays. The reviewer will not lock these address-change numbers as a held gate.

## 0h. Reviewer lock (2026-08-22) — aaf601ca + 5942beaa stay; W0 is still open

Keep `eddd0b57` and `9d80ecd6`. Do not re-bench `4ea1dcf3` + `a5b945da`. Keep `aaf601ca` (hyprbars + omarchy-minimize built into `/usr/lib/hyprland-plugins`, no hyprpm). Keep `5942beaa` (idle Start is Chrome and Files; foot and vim stay installed and searchable, they are not the front of the OS). The last two commits stay (`5942beaa`, `a4a046b3`). Do not amend them. Do not squash them.

Windowing is still not a go. Bench stays idle.

What actually moved:

- Title bars and hide survive a wiped user cache. Live maps are `/usr/lib/hyprland-plugins/hyprbars.so` and `/usr/lib/hyprland-plugins/omarchy-minimize.so`. Minimize is `CWindow::setHidden` on the same workspace, not `special:minimized`. Overlay chrome is still gone.
- The QEMU postage stamp was virtio-vga coming up `640×480`; grim at 1080p was a lie. The GTK window is the proof.
- SearchBox using Qt’s stock white field was a real Start bug.

What did not move:

- hyprbars is still not an ISO-mirror pacman package. The AUR name still must not go in `install/omarchy-other.packages`.
- Alt+Tab address-change is still not a held number this lock will accept.
- This guest Start only listing foot and vim is a disk contents problem, not a reason to make the terminal first-class.
- Tokyo Night, generic gear icons, Nautilus, nvim, TTY first-boot, no product ISO — still open.
- Chrome, games, and “install any Windows app” are still not a live path.

Plans still win: `PRODUCT_DOCTRINE.md` plus `plans/project-ultimate.md`. Windows 7 Ultimate information architecture for 2026. Every normal Windows job has to work with a mouse. Terminal stays a powerful app. It is not how you own the machine. The written “not a clone” line is ads, telemetry, and forced accounts — not permission to ship a Linux developer box.

## 0i. W0 Tranche G (2026-08-22) — mouse window manager; W0 is still open

Keep `aaf601ca`, `5942beaa`, and `a4a046b3`. Do not re-open them. Windowing is still not a go.

Moved on the live guest (Virtual-1 1920×1080, reserved `[0,0,0,40]`):

- Quarters: Win+Arrow left then up is `[0,32] 960×504`. Halves stay `[0,32] 960×1008` / `[960,32] 960×1008`.
- Snap chooser layer `omarchy-snap-chooser` 1920×1080. hyprbars `▦` and Win+Z summon it.
- `aeroDragEnd` uses cursor coordinates. Top-center `960,0` maximizes `[2,34] 1916×1004` fullscreen `1`. Interior `960,400` restores the remembered float `[208,80] 880×560`.
- `saveLayout` / `restoreLayout` return the same two halves after an unsnap. Match is by compositor address.
- Show Desktop hides both feet (`hidden: true`, workspace `1`) and restores them.
- Grouped taskbar click cycles; peek lists each window title (not bitmap Aero Peek).

Did not move: Alt+Tab as a held number; peek thumbnails / jump lists; multi-monitor; virtual desktops; parented dialogs; Steam/Wine/Electron matrix; hyprbars as a pacman package; Tokyo Night, Nautilus, nvim, TTY, ISO.

The GTK window is the proof. Do not treat this tranche as a windowing go.

## 0j. W0 windowing GO (2026-08-22) — product still rejected

KEEP `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not squash them. Do not restore `e90d75c8`'s `--disable-features=WaylandWindowDecorations`.

Windowing Gate W0 is **GO** on the metal box (HDMI-A-1 1920×1080@60, reserved `[0,0,0,40]`). That is not an OS go. Do not merge PR #1 as the product.

KEEP-WITH-FIX that landed:

- hyprbars caption actions format the bar owner: `omarchy-shell window close 0x{:x}` (and maximize / snapChooser / minimize). `closeActive` / `active` on an unfocused SSD bar can kill the focused window. Live: two feet `0x55cc1a5f03b0` / `0x55cc15ae4b40`; addressed close unmapped B; A stayed. Rebuilt `/usr/lib/hyprland-plugins/hyprbars.so` 397224 bytes.
- `hyprbars:no_bar` matches Chromium/Firefox/Cursor **class**, plus the YouTube/Zoom PWA class regex. Those PWAs drop `chromium-based-browser` for opacity; they must not grow a second bar.
- One-row Chromium CSD re-shot after `3a545547` + `c1ae994f`: maximized `[1,1] 1918×1038` fullscreen `1`, origin border `(106,106,106)`, `hyprbars_red_close_px 0`. Tab strip fused with min/max/close; omnibox under that is Chromium UI, not a second OS title bar.

Still not the OS (later phases, not this slice): ISO, gum, Tokyo Night seed, Nautilus-as-Files, nvim-as-txt, TTY first-boot, Steam/.exe, hyprbars as an ISO-mirror pacman package. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.

Historical next-line (superseded): design system. **Current next work is Agent Fabric + Superbar plugin/`omarchy.agents` visibility** — see Current lock.

## 1. Read-first contract (mandatory, non-skippable)

Before writing a single line of code, running a test, or booting a VM, read these files in full, in this order. They are the Project Ultimate source of truth and they override intuition, memory, and habit.

1. `PRODUCT_DOCTRINE.md` — the locked identity (Windows 7 Ultimate desktop model + agent-native fabric; not Windows-like Omarchy with AI tools) and the eight non-negotiable rules (zero-terminal ownership, zero-hotkey-required operation, "Windows muscle memory is an API", visible-before-memorable, progressive disclosure, all consequential operations have state, recoverability is a flagship feature, **agent-native same capability graph**), plus naming/error doctrine and Mode Profiles.
2. `WINDOWS_NATIVE_ACCEPTANCE.md` — the forty-task smoke test (necessary, not sufficient; six numbered rows automated, plus unnumbered harness proofs after the loop). This slice owned rows 20–25 (pin, unpin, minimize three, restore the one they want, snap two, Alt+Tab). Also read `WINDOWS_7_ULTIMATE_PARITY.md` and `AGENT_NATIVE_ACCEPTANCE.md`.
3. `docs/mode-profiles.md` — one toggle, two profiles, one platform: feature-flag resolution (flags mean capability exists), the shell overlay rule (Desktop Mode must not rewrite `~/.config/omarchy/shell.json`), Superbar plugin/`omarchy.agents` visibility, and the Hyprland state-file selection.
4. `docs/settings-service-api.md` — the architecture rule: UI and agents → typed service verbs → existing Omarchy/system tooling. QML never spawns shell commands directly. WindowService is the first provider; Agent Fabric is the next gate.
5. `docs/design-tokens.md` and `docs/omarchy-shell.md` — the semantic token layer and the shell/plugin/IPC contract.
6. `AGENTS.md` (repo root) plus the task guides it points to: `agents/skills/shell-dev.md`, `agents/skills/acceptance-tests.md`, `agents/skills/visual-verification.md`, and `docs/testing.md`.
7. `default/ultimate/profiles/desktop.json` and `default/ultimate/profiles/power-user.json` — the shipped profile data.

Acknowledgement gate: in your first substantive reply, restate the eight doctrine rules in your own words and name the mode-profiles overlay rule and the settings-service architecture rule. Do not proceed until you have done this. If any listed file is missing, stop and report drift rather than guessing.

## 2. Ground truth: repository state

- Remote: `github.com/jnadeau207-collab/omarchy-7-ultimate`. Default branch: `main` (clean upstream tracking). Work branch: `work` (all Ultimate product commits, including the locked W0 stack through `c1ae994f`, later `c1d6e6a6`, quattro merge, and doctrine on `work`).
- Do not reconstruct deleted slice branches (`ultimate/foundation`, `cursor/desktop-mode-slice-00d6`, `cursor/cloud-agent-dev-environment-a448`). Those named tips are ancestors of `work` (`c1d6e6a6`, `4c3e985b`, PR #2 `28a8bdfb`). The extra GitHub merge SHA on the cloud-agent tip (`30aac92f`) is **not** an ancestor of `work`; both parents are, unique blobs 0, `git diff --diff-filter=A work 30aac92f` empty. Ledger: `C:\dev\omarchy-vm\branch-reconciliation-ledger-2026-08-22.md`. Bundle: `C:\dev\omarchy-vm\omarchy-all-refs-2026-08-22.bundle` (251209890 bytes, 145 refs, verify okay). At ledger time `work` was `c4c6ce29` (35 ahead / 0 behind `main` `2c247e39` == quattro). Later docs commits moved `work` — do not reset. Zero unique Jesse **content**; do not claim zero unique Jesse **commits**.
- Product is still REJECTED. W0 is architecture GO. Do not merge `work` into `main` as the OS.
- Continue on `work`. Do not create new branches. Do not force-push. Do not amend locked SHAs `4ea1dcf3` through `c1ae994f`. Do not edit the external `.plan.md` file that lives on the developer's machine.

Fetch and check out before doing anything else:

```bash
git fetch origin --prune
git checkout work
git pull origin work
git log --oneline -1
```

## 3. What is already proven (do not redo blindly, but re-run to confirm)

Automated, compositor-free coverage is green:

- `./test/cli` — 116 ok, 0 fail.
- `./test/shell` — 2314 ok. The only failures are `config-test.sh`, `snapper-test.sh`, and `unowned-system-paths-test.sh`, and only because they require a checkout of the separate private `omarchy-pkgs` repo (they scan its `PKGBUILD`s). Point `OMARCHY_PKGS_PATH` at a sibling checkout to clear them; otherwise treat exactly those three as expected-absent, never as regressions.
- Desktop Mode unit/static coverage passes: `mode-profile-test.sh`, `ultimate-desktop-plugin-test.sh`, `window-service-test.sh`, the desktop entries in `hyprland-default-config-test.sh` and `hyprland-binding-conflicts-test.sh`.

Run the whole non-graphical suite from a login shell so the environment's `OMARCHY_PATH` and `bin/` on `PATH` are present:

```bash
bash -lc 'cd "$(git rev-parse --show-toplevel)" && ./test/all'
```

Critical caveat: every compositor-dependent test prints `no Wayland compositor; skipping …`. The green suite does not prove windowing behavior. That is the entire reason for this handoff.

## 4. The mission now: Agent Fabric, not a second windowing go/no-go

W0 architecture already passed on metal. Do not re-run the windowing go/no-go as if minimize were still `special:minimized`. Minimize is `CWindow::setHidden`. Overlay captions are gone.

The next slice is Agent Fabric contract (WindowService first provider) and restoring `omarchy.agents` / plugin visibility on the Superbar. Do not start a huge design-system or Desktop Mode visual pass that treats agents as optional later.

If a later turn must re-prove windowing, use §6 as the old checklist and the Current lock for remaining product-windowing debt. A QML service that fires Lua dispatchers is still not the OS.

## 5. Stand up the guest (do not skip, do not fake)

Use a real Omarchy guest so the actual `default/hypr` config, the running Quickshell shell, and real applications are exercised. Two supported paths:

- Reuse the developer's existing guest disk. The portable launcher is `test/vm/vm-run.ps1`:

  ```powershell
  # Windows host, hardware acceleration when available (WHPX) else TCG:
  pwsh -File test/vm/vm-run.ps1 -Disk C:\dev\omarchy-vm\arch.qcow2 -Accel whpx
  # Inspect the resolved command without launching:
  pwsh -File test/vm/vm-run.ps1 -ListOnly
  ```

  The launcher only boots a machine; it does not install anything. Boot into a Desktop Mode session (Desktop Mode is the default; confirm with `omarchy mode get`).

- Full acceptance path through the sibling `omarchy-iso` repository, per `agents/skills/acceptance-tests.md`. Sync local `bin/`, `config/`, and `shell/` so the guest runs this checkout:

  ```bash
  cd ../omarchy-iso
  ./bin/omarchy-iso-test release/<iso>.iso --reuse-base --sync-all ../omarchy-7-ultimate --no-preview
  ```

  Rebuild a fresh ISO without `--reuse-base` if you touched packaging, installation, finalization, or shipped defaults.

Inside the guest, confirm the compositor and shell are live before testing: `hyprctl monitors -j` must answer, and `omarchy-shell window ping` must return. The `omarchy-shell window <verb>` IPC target and `hyprctl` are how you drive and observe every check below.

## 6. Windowing go/no-go (acceptance rows 20–25 plus core behaviors)

The executable gate is `test/acceptance.d/windows-native-test.sh`, which already implements rows 20–25 against `omarchy-shell window …` and `hyprctl -j clients`. Run it inside the live guest session (directly, or through the `omarchy-iso` harness which also collects `success-*.png`/`failure-*.png`). Capture a screenshot of each distinct state; save the passing set as walkthrough artifacts.

Prove each of these with evidence, not assertion:

- Overlapping float: launch three windows (`foot`), confirm each is floating and they overlap (`hyprctl -j clients` shows `floating: true` and intersecting `at`/`size`), not tiled.
- Title-bar drag moves; edge/corner drag resizes. `default/hypr/desktop-windows.lua` sets `resize_on_border = true` and floats by default; confirm the border resize and drag actually work in the session.
- Maximize is real and not suppressed: maximize an active window and confirm it fills the work area (respecting the bar) and restores. This is the first place a dispatcher bug will surface — see §7.
- Minimize three, then restore the specific one: minimize is `CWindow::setHidden` on the same workspace via `omarchy-minimize` (not `special:minimized`). Restoring must return the exact same window (same address) with title/app identity intact. Historical text below that still names `special:minimized` is pre-Tranche-D evidence.
- Snap two windows: snap one left and one right; confirm each matches the Hyprland 0.56 work area (`reserved` is **left, top, right, bottom**). A bottom taskbar of 40px on 1920×1080 is left `[0,0] 960×1040` and right `[960,0] 960×1040`. `at[0] <=` plus non-zero width is not enough.
- Maximize fills that same work area (`fullscreen == 1`, size within 32px of work width/height). This is required even though it is not a numbered acceptance row.
- Alt+Tab: cycle raises the task-switcher overlay; cards are clickable; commit focuses the chosen window.

Do not call this a go from IPC-only green, from screenshots that are not in the repo, or from a handoff writeup. The bar is a Windows 7 Ultimate desktop on Omarchy, mouse-first, not a theme. A QML service that fires Lua dispatchers is not that product.

## 7. Live compositor findings (Hyprland 0.56.2)

Classic token dispatchers are dead. `hyprctl dispatch fullscreen 2`, `movewindowpixel`, `resizeactive`, and `movetoworkspacesilent` fail on the Lua parser. Working forms, always with `window = "address:0x…"`:

- Maximize: `hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = "address:…" })`. Omitting `action` toggles.
- Snap: ordered `hl.dsp.window.float({ action = "enable" })`, then `resize({ x, y, relative = false })`, then `move({ x, y, relative = false })`. Percent sizes are rejected. Pixels come from the focused monitor's work area.
- Minimize (historical, superseded by Tranche D): `hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:…" })` was the 0.56 debug path. Current minimize is `hl.plugin.omarchy_minimize.*` / `CWindow::setHidden` on the same workspace.
- Restore: Lua move to `Hyprland.focusedWorkspace.id` with `follow = true`. `Toplevel.activate()` on a parked client does not restore it.

How dispatch is fired from QML:

- `Qt.createQmlObject("… Process {}")` as a child of the WindowService `QtObject` never starts.
- A named `Process` queue drops independent verbs (`running = true` inside `onExited` is ignored).
- `Quickshell.execDetached(["hyprctl", …])` plus `bash -c` with a raw address interpolates shell and breaks the typed-service rule (UI → typed verb → tooling). Use `Hyprland.dispatch(expr)`.

Reserved axes (the snap `[40,0] 940×1080` bug): Hyprland 0.56 JSON `reserved` is **`[left, top, right, bottom]`** (`m_reservedArea.left/top/right/bottom` in HyprCtl.cpp). A bottom taskbar reports `[0,0,0,40]`. Reading that as the older wiki `[top, right, bottom, left]` treats 40 as a left inset. `WindowModel.reservedLTRB` / `snapRect` lock the 0.56 order. The taskbar also sets `ExclusionMode.Normal` and `exclusiveZone` so the bottom edge is explicit.

Wayland `Toplevel.address` is empty. Taskbar groups, Alt+Tab, and caption chrome must use `Hyprland.toplevels` addresses (`0x`-canonicalized). Comparing `Toplevel.address` for `isActive` focuses the wrong window.

Shell load:

- Bare `FileView`/`Process` children of `QtObject` fail. Named `property FileView` / `property Process` load.
- `Taskbar.qml` must not `require` `omarchyPath`; injection is too late in `configureBar` onLoaded.
- `Loader.errorString` is a property, not a function.
- A `PanelWindow` with only `implicitWidth`/`implicitHeight` never maps. Screen-edge anchors map the task switcher.

## 7b. Reviewer rejection of the dispatcher turn

The turn that landed `a7b2c093` + `18370335` was **REJECTED**. Do not call windowing a go from that work. It was useful as 0.56 dispatcher debug. It was not implementation. Locked findings from that review, still in force unless a later live proof contradicts them:

- Windowing is not a WM without title-bar chrome, glass, peek, clickable Alt+Tab, and taskbar clicks that hit the button's address.
- Minimize via `special:minimized` is not a Windows minimize.
- Snap used the wrong reserved axes; `[40,0] 940×1080` was that bug.
- Maximize was missing from the harness; snap only checked left x ≤ right x.
- Rows 20–25 "passed" without repo screenshots and without mouse.
- Default theme, Start-as-hamburger, monospace, Super+E → Nautilus, nvim for text, no product ISO, TTY first boot, unreproducible VM recipe (no disk/ISO/guest agent in the product repo) mean this is not the OS.

This file must not grade the session. A later turn that ships caption chrome and LTRB snap still does not make Tokyo Night + a TTY first boot into Windows 7 Ultimate.

Live numbers from the follow-up turn (Hyprland 0.56.2, virtio-vga 1920×1080, reserved `[0,0,0,40]` as left/top/right/bottom). These are evidence, not a go. **Superseded for snap/SSD by §0b** (1054 height and overlay captions are the pre-Tranche-B state):

- Taskbar layer `omarchy-taskbar` at `x=0 y=1040 w=1920 h=40`. Exclusive zone is the bottom edge.
- IPC snap via `Hyprland.dispatch`: left `[0,0] 960×1054`, right `[960,0] 960×1054`. The old `[40,0] 940×1080` left-inset geometry is gone. Height is 14px taller than the 1040px work area (within the harness 32px slop).
- Maximize: `fullscreen: 1`, `[2,2] 1916×1036`.
- Minimize identity: both feet on workspace `-98`; restore of `0x555bafb7f480` returned that address to workspace 1 with title intact.
- Caption layer `omarchy-window-chrome` maps. Start button text is `Start`, not a hamburger.
- Default theme, Nautilus, nvim, TTY first boot, and the missing product ISO are unchanged.

## 8. Non-negotiable engineering rules for the code you write

- Architecture: UI and agents → typed service verbs → Omarchy/system tooling. QML components never spawn shell commands; window operations go through `WindowService` verbs. New capability domains are QML singletons under `shell/services/` with structured readers and intent-named writers returning `{ changed, error: { title, explanation, detail } }` (`docs/settings-service-api.md`). Agent Fabric brokers those same verbs; do not add a parallel shell-string agent path.
- Mode profiles are data. UI registers against feature flags, never against mode strings. Flags mean capability exists. Desktop Mode must not rewrite `~/.config/omarchy/shell.json`; it computes an effective config in `shell.qml`. Switching modes must not require a reboot or lose user state (`docs/mode-profiles.md`). Superbar must keep the Quattro plugin model; do not treat `TrayCluster.qml`'s hard-coded list as finished.
- Runtime paths come from `$OMARCHY_PATH` / `Quickshell.env("OMARCHY_PATH")`. Do not derive fallback paths from `HOME` or `Quickshell.shellDir`, and do not re-export or default `OMARCHY_PATH`.
- Bash style (`AGENTS.md`): `#!/bin/bash` shebangs; `[[ ]]` for string/file tests and `(( ))` for numeric; quote string literals in comparisons but not bare variables inside `[[ ]]`; two-space indent, no tabs; quote paths with spaces rather than escaping.
- Commands are `omarchy-*` with purposeful prefixes; keep `GROUP_DESCRIPTIONS` in `bin/omarchy` current; every executable under `bin/` carries a `# omarchy:summary=` header. Use helper commands (`omarchy-pkg-add`, `omarchy-cmd-present`, `omarchy-notification-send`, …) instead of raw equivalents.
- Shell/QML editing: run `omarchy-restart-shell` after QML changes; do not rewrite Nerd Font glyph widget files wholesale (`agents/skills/shell-dev.md`). Verify any visual change in the running UI, not just in an artifact (`agents/skills/visual-verification.md`).
- Markdown docs (`plans/`, `docs/`, `manual/`): full lines, no hard wrapping at 80 columns; break only at structural boundaries.
- Git: atomic commits, one coherent change each, succinct messages. Do not force-push or amend. Do not merge PRs or enable auto-merge.

## 9. Explicit do-not list

- Do not reconstruct deleted slice branches from memory; they are ancestors of `work`.
- Do not edit the developer's local `.plan.md`.
- Do not skip a live compositor when changing windowing, and do not substitute a non-Hyprland compositor (Sway/Weston) — its dispatchers and behavior differ and prove nothing here.
- Do not hide a minimize identity failure behind taskbar chrome. Report it. Minimize is `setHidden`, not `special:minimized`.
- Do not commit dispatcher changes that were never run on a live compositor.
- Do not commit VM images, disks, or scratch artifacts into the repo.
- Do not call the OS a go from IPC-only harness green, from screenshots that are not in the repo, or from this handoff. W0 architecture GO is already recorded; that is not an OS go.
- Do not re-review `4ea1dcf3` + `a5b945da` as a product pass. Do not re-run the full bench on that writeup. Do not re-open `eddd0b57` / `9d80ecd6` / `aaf601ca` / `5942beaa` / `a4a046b3`. Next review is when a new turn actually moves a locked gate (Agent Fabric or Superbar plugin visibility, not a recap of W0).
- Do not treat Alt+Tab address-change as a locked number. Do not treat a painted-card click that only hides the overlay as activate-the-other-foot.
- Do not grade grim as the QEMU window. The GTK window is the proof. virtio-vga `preferred` was `640×480`.
- Do not make foot/vim first class because a guest disk lacked consumer apps.
- Do not add `aliases` to new menu entries.
- Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Do not load hyprbars from `/var/cache/hyprpm/`.
- Do not restore `--disable-features=WaylandWindowDecorations`.
- Do not start a huge Phase 3/4 visual pass that assumes agents are optional later. Do not hide `omarchy.agents` in Desktop Mode while waiting for Agent Center.

## 10. Definition of done

- The read-first contract in §1 is satisfied and acknowledged (eight rules, overlay rule, typed-service rule, Agent-Native).
- `./test/all` is green except the three `omarchy-pkgs`-dependent files (or fully green with `OMARCHY_PKGS_PATH` set). Counts in §3 were last recorded in an earlier session; re-run rather than citing them as this turn.
- W0 architecture remains GO: snap geometry is LTRB work-area, maximize is in the harness, taskbar clicks use Hyprland addresses, Alt+Tab cards are clickable, captions are hyprbars, minimize is `setHidden`. Remaining product-windowing debt stays listed in the Current lock — do not paper it over.
- Next product slice done only when Agent Fabric contract work and/or Superbar `omarchy.agents`/plugin visibility actually land — not when another taskbar restyle ships.
- Visual verification done for every UI-affecting change.
- Work is committed only when asked; do not amend `c253d193` / `a7b2c093` / `18370335` / `4ea1dcf3` / `a5b945da` / `eddd0b57` / `9d80ecd6` / `aaf601ca` / `5942beaa` / `a4a046b3` / `c1ae994f`.
- This slice is still not the OS: Tokyo Night, generic gear icons, Nautilus, nvim, TTY first boot, Chrome/games/Windows-app install, Agent Fabric, Agent Center, and the missing product ISO remain later work. Do not paper over them in the handoff.
