# Desktop Mode Slice — Local Session Handoff

This is a binding handoff for a fresh session running on the developer's local machine, where a real QEMU guest with a live Hyprland session is available. It exists because the windowing go/no-go cannot be proven in the cloud pod: that pod has `/dev/kvm` but a degraded virtualization stack (a trivial QEMU freezes its own monitor loop, no guest serial output, no loadable kernel modules), so no faithful Hyprland session can be stood up there. Everything that does not need a live compositor has already been verified; what remains is the compositor-level proof and any fixes that proof justifies.

Do not treat this file as advisory. It is a contract. Follow it in order and do not skip.

## 0. Reviewer lock (2026-08-22)

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

Idle Start was listing AppSearch sort wrappers as apps, so the menu led with **foot** and **vim** and generic gear icons. Start now unwraps `.entry`, hides developer tools unless the user is searching (`developerToolsInStart` is false on the desktop profile), and loads shipped pins Chrome and Files when the user has no `taskbar-pins.json`. Search still finds foot/vim.

## 1. Read-first contract (mandatory, non-skippable)

Before writing a single line of code, running a test, or booting a VM, read these files in full, in this order. They are the Project Ultimate source of truth and they override intuition, memory, and habit.

1. `PRODUCT_DOCTRINE.md` — the objective and the seven non-negotiable rules (zero-terminal ownership, zero-hotkey-required operation, "Windows muscle memory is an API", visible-before-memorable, progressive disclosure, all consequential operations have state, recoverability is a flagship feature), plus naming/error doctrine and the Mode Profiles concept.
2. `WINDOWS_NATIVE_ACCEPTANCE.md` — the forty-task release gate. This slice owns rows 20–25 (pin, unpin, minimize three, restore the one they want, snap two, Alt+Tab).
3. `docs/mode-profiles.md` — one toggle, two profiles, one platform: feature-flag resolution, the shell overlay rule (Desktop Mode must not rewrite `~/.config/omarchy/shell.json`), and the Hyprland state-file selection.
4. `docs/settings-service-api.md` — the architecture rule: UI → typed service verbs → existing Omarchy/system tooling. QML never spawns shell commands directly.
5. `docs/design-tokens.md` and `docs/omarchy-shell.md` — the semantic token layer and the shell/plugin/IPC contract.
6. `AGENTS.md` (repo root) plus the task guides it points to: `agents/skills/shell-dev.md`, `agents/skills/acceptance-tests.md`, `agents/skills/visual-verification.md`, and `docs/testing.md`.
7. `default/ultimate/profiles/desktop.json` and `default/ultimate/profiles/power-user.json` — the shipped profile data.

Acknowledgement gate: in your first substantive reply, restate the seven doctrine rules in your own words and name the mode-profiles overlay rule and the settings-service architecture rule. Do not proceed until you have done this. If any listed file is missing, stop and report drift rather than guessing.

## 2. Ground truth: repository state

- Remote: `github.com/jnadeau207-collab/omarchy-7-ultimate`. Default branch: `quattro`.
- Foundation branch: `ultimate/foundation` (tip `4c3e985b`, WindowService). Do not reconstruct or re-derive it; it is on the remote and the slice stacks on it.
- Work branch: `cursor/desktop-mode-slice-00d6`. Accepted repair tips: `4ea1dcf3` (windowing) + `a5b945da` (roadmap). Product call on that pair is REJECTED. Do not treat HEAD as a windowing go.
- Open PR for the slice: #1.
- Continue on `cursor/desktop-mode-slice-00d6`. Do not switch branches, do not force-push, do not amend existing commits, and do not edit the external `.plan.md` file that lives on the developer's machine.

Fetch and check out before doing anything else:

```bash
git fetch origin --prune
git checkout cursor/desktop-mode-slice-00d6
git pull origin cursor/desktop-mode-slice-00d6
git log --oneline -1   # expect a5b945da or a later commit that actually moved a locked gate
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

## 4. The mission: prove conventional windowing on Hyprland, then finish the slice

From the plan: prove conventional windowing on Hyprland (or stop), then ship Desktop Mode as a real product surface — profile-driven bottom taskbar, a Start that launches apps, pin/unpin, Show Desktop, and Windows keybindings — verified in the QEMU guest. The windowing proof is the gate. If `special:minimized` cannot restore a window with its identity intact, that is a compositor gate to surface honestly, not something to paper over with taskbar chrome.

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
- Minimize three, then restore the specific one: minimize sends to `special:minimized`; restoring must return the exact same window (same address) to the active workspace with its title/app identity intact. This is the compositor gate. If identity is lost, stop and report it as a go/no-go failure.
- Snap two windows: snap one left and one right; confirm each matches the Hyprland 0.56 work area (`reserved` is **left, top, right, bottom**). A bottom taskbar of 40px on 1920×1080 is left `[0,0] 960×1040` and right `[960,0] 960×1040`. `at[0] <=` plus non-zero width is not enough.
- Maximize fills that same work area (`fullscreen == 1`, size within 32px of work width/height). This is required even though it is not a numbered acceptance row.
- Alt+Tab: cycle raises the task-switcher overlay; cards are clickable; commit focuses the chosen window.

Do not call this a go from IPC-only green, from screenshots that are not in the repo, or from a handoff writeup. The bar is a Windows 7 Ultimate desktop on Omarchy, mouse-first, not a theme. A QML service that fires Lua dispatchers is not that product.

## 7. Live compositor findings (Hyprland 0.56.2)

Classic token dispatchers are dead. `hyprctl dispatch fullscreen 2`, `movewindowpixel`, `resizeactive`, and `movetoworkspacesilent` fail on the Lua parser. Working forms, always with `window = "address:0x…"`:

- Maximize: `hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = "address:…" })`. Omitting `action` toggles.
- Snap: ordered `hl.dsp.window.float({ action = "enable" })`, then `resize({ x, y, relative = false })`, then `move({ x, y, relative = false })`. Percent sizes are rejected. Pixels come from the focused monitor's work area.
- Minimize: `hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:…" })`. Identity at the compositor holds: restoring the same address returns it to the active workspace with title intact. Parking on `special:minimized` is still a compositor trick, not a Windows minimize, until caption chrome and the taskbar are the mouse path.
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

- Architecture: UI → typed service verbs → Omarchy/system tooling. QML components never spawn shell commands; window operations go through `WindowService` verbs. New capability domains are QML singletons under `shell/services/` with structured readers and intent-named writers returning `{ changed, error: { title, explanation, detail } }` (`docs/settings-service-api.md`).
- Mode profiles are data. UI registers against feature flags, never against mode strings. Desktop Mode must not rewrite `~/.config/omarchy/shell.json`; it computes an effective config in `shell.qml`. Switching modes must not require a reboot or lose user state (`docs/mode-profiles.md`).
- Runtime paths come from `$OMARCHY_PATH` / `Quickshell.env("OMARCHY_PATH")`. Do not derive fallback paths from `HOME` or `Quickshell.shellDir`, and do not re-export or default `OMARCHY_PATH`.
- Bash style (`AGENTS.md`): `#!/bin/bash` shebangs; `[[ ]]` for string/file tests and `(( ))` for numeric; quote string literals in comparisons but not bare variables inside `[[ ]]`; two-space indent, no tabs; quote paths with spaces rather than escaping.
- Commands are `omarchy-*` with purposeful prefixes; keep `GROUP_DESCRIPTIONS` in `bin/omarchy` current; every executable under `bin/` carries a `# omarchy:summary=` header. Use helper commands (`omarchy-pkg-add`, `omarchy-cmd-present`, `omarchy-notification-send`, …) instead of raw equivalents.
- Shell/QML editing: run `omarchy-restart-shell` after QML changes; do not rewrite Nerd Font glyph widget files wholesale (`agents/skills/shell-dev.md`). Verify any visual change in the running UI, not just in an artifact (`agents/skills/visual-verification.md`).
- Markdown docs (`plans/`, `docs/`, `manual/`): full lines, no hard wrapping at 80 columns; break only at structural boundaries.
- Git: atomic commits, one coherent change each, succinct messages. Do not force-push or amend. Do not merge PRs or enable auto-merge.

## 9. Explicit do-not list

- Do not reconstruct `ultimate/foundation` from memory; it is on the remote.
- Do not edit the developer's local `.plan.md`.
- Do not skip the live windowing go/no-go, and do not substitute a non-Hyprland compositor (Sway/Weston) — its dispatchers and behavior differ and prove nothing here.
- Do not hide a `special:minimized` identity failure behind taskbar chrome. Report it.
- Do not commit dispatcher changes that were never run on a live compositor.
- Do not commit VM images, disks, or scratch artifacts into the repo.
- Do not call windowing a go from IPC-only harness green, from screenshots that are not in the repo, or from this handoff.
- Do not re-review `4ea1dcf3` + `a5b945da` as a product pass. Do not re-run the full bench on that writeup. Do not re-open `eddd0b57`. Next review is when a new turn actually moves a locked gate.
- Do not treat a painted-card click that only hides the Alt+Tab overlay as activate-the-other-foot.
- Do not add `aliases` to new menu entries.
- Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Do not load hyprbars from `/var/cache/hyprpm/`.

## 10. Definition of done

- The read-first contract in §1 is satisfied and acknowledged.
- `./test/all` is green except the three `omarchy-pkgs`-dependent files (or fully green with `OMARCHY_PKGS_PATH` set).
- Snap geometry is LTRB work-area, maximize is in the harness, taskbar clicks use Hyprland addresses, Alt+Tab cards are clickable, and caption chrome exists as mouse affordances. Live proof is hyprctl geometry plus mapped layers, not a self-graded go.
- Visual verification done for every UI-affecting change.
- Work is committed only when asked; do not amend `c253d193` / `a7b2c093` / `18370335` / `4ea1dcf3` / `a5b945da` / `eddd0b57` / `9d80ecd6`.
- This slice is still not the OS: Tokyo Night, Nautilus, nvim, TTY first boot, and the missing product ISO remain later work. Do not paper over them in the handoff.
