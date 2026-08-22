# Desktop Mode Slice — Local Session Handoff

This is a binding handoff for a fresh session running on the developer's local machine, where a real QEMU guest with a live Hyprland session is available. It exists because the windowing go/no-go cannot be proven in the cloud pod: that pod has `/dev/kvm` but a degraded virtualization stack (a trivial QEMU freezes its own monitor loop, no guest serial output, no loadable kernel modules), so no faithful Hyprland session can be stood up there. Everything that does not need a live compositor has already been verified; what remains is the compositor-level proof and any fixes that proof justifies.

Do not treat this file as advisory. It is a contract. Follow it in order and do not skip.

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
- Work branch: `cursor/desktop-mode-slice-00d6` (tip `103d28b1`). It stacks on the foundation and already contains the merged Cloud Agent environment (`.cursor/environment.json`, `.cursor/install.sh` from PR #2).
- Open PR for the slice: #1.
- Continue on `cursor/desktop-mode-slice-00d6`. Do not switch branches, do not force-push, do not amend existing commits, and do not edit the external `.plan.md` file that lives on the developer's machine.

Fetch and check out before doing anything else:

```bash
git fetch origin --prune
git checkout cursor/desktop-mode-slice-00d6
git pull origin cursor/desktop-mode-slice-00d6
git log --oneline -1   # expect 103d28b1 or a later commit on this branch
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
- Snap two windows: snap one left and one right; confirm left/right geometry (`$l.at[0] <= $r.at[0]`, both non-zero width) as the harness checks.
- Alt+Tab: cycle raises the task-switcher overlay and commit focuses the chosen window.

Go = every row 20–25 passes live with screenshots and the four core behaviors (overlap, drag, resize, maximize, minimize/restore identity) hold. No-go = any of them fails; document exactly which, with the `hyprctl -j clients` output and a screenshot, before changing code.

## 7. Findings to verify live, then fix with proof (do not pre-apply blind)

These came from reading `shell/services/WindowService.qml` against the Hyprland dispatcher reference (`https://wiki.hypr.land/`). They are hypotheses backed by documentation, not confirmed on a live compositor. Confirm each in the running guest first; then fix minimally and re-run the go/no-go so the fix is proven, never assumed.

- `maximize()` dispatches `fullscreen 2`. The `fullscreen` dispatcher accepts only mode `0` (fullscreen) or `1` (maximize); there is no mode `2`. Expected correct call: `fullscreen 1`. Verify what `fullscreen 2` actually does in the pinned Hyprland version before changing it.
- `_snapActive()` calls `movewindowpixel exact …` with no window target. `movewindowpixel` takes `resizeparams,window`; the dispatcher that moves the active window is `moveactive`. Expected correct call: `moveactive exact 0 0` (left) and `moveactive exact 50% 0` (right), paired with the existing `resizeactive exact 50% 100%`.
- `_snapActive()` issues `setfloating`, `resizeactive`, and the move as three independent asynchronous `hyprctl` processes with no ordering guarantee — a race. Dependent dispatches should be one ordered request (`hyprctl --batch "dispatch …; dispatch …; dispatch …"`) behind a typed service verb.
- `maximize()`, `snapLeft()`, and `snapRight()` call `focus()` (async `activate()`) and then immediately dispatch against the active window — another ordering race. Prefer addressing the target window explicitly (`address:<addr>`) inside the batched request instead of relying on focus landing first.
- `restore()` / `minimize()` identity across `special:minimized` (§6) is behavior, not syntax; only the live run settles it.

If a live check contradicts a hypothesis, trust the live result and update this section's premise; do not force the documented behavior onto a version that differs.

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
- Do not add `aliases` to new menu entries.

## 10. Definition of done

- The read-first contract in §1 is satisfied and acknowledged.
- `./test/all` is green except the three `omarchy-pkgs`-dependent files (or fully green with `OMARCHY_PKGS_PATH` set).
- Acceptance rows 20–25 pass live in the guest with saved `success-*.png` screenshots, and the four core behaviors (overlap, drag, resize, maximize, minimize/restore identity) are demonstrated.
- Any §7 fix that was applied is backed by a before/after live run, and the relevant `test/shell.d` coverage is updated to lock the corrected behavior in.
- Visual verification done for every UI-affecting change.
- Work committed in atomic commits on `cursor/desktop-mode-slice-00d6`, pushed, and PR #1 updated with the go/no-go evidence.
- If windowing is a no-go, the slice stops at an honest, documented compositor gate instead of shipping chrome over a broken foundation.
