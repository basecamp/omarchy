# W0 Tranche F — Alt+Tab address-change

Worker slice after Tranche E. It is not a windowing go. Keep `eddd0b57`, `9d80ecd6`, `aaf601ca`, and `5942beaa`. Do not re-open those SHAs. Do not re-bench `4ea1dcf3` + `a5b945da`.

Read with `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md`, `plans/desktop-mode-handoff.md`. Doctrine wins on conflict.

## Doctrine (this slice still obeys)

1. Zero-terminal ownership — switching windows is a mouse click on a card, not hyprctl.
2. Zero-hotkey-required — Alt+Tab cards are the path; Alt+Tab itself is an accelerator.
3. Windows muscle memory is an API — the highlighted / clicked card becomes the active window.
4. Visible before memorable — the switcher paints cards; the result is the other window in front.
5. Progressive disclosure — not this slice.
6. Consequential operations have state — activation has a held address, not “overlay went away.”
7. Recoverability — not this slice.

Overlay rule: Desktop Mode still must not rewrite `shell.json`.

Service rule: QML still calls `WindowService.activate`; it does not assemble `hyprctl` around an address.

## Why this tranche

Tranche C proved hyprbars close/drag with an absolute pointer. A painted-card click that only hid `omarchy-task-switcher` is not activate-the-other-foot. That was the remaining W0 gate that can move without `omarchy-pkgs` (hyprbars-as-pacman) and without starting Phase 2–9.

## Root cause

`activateFromSwitcher` / `commitCycle` called `restore()`, which only unhides. Two visible feet: restore does not raise the other window.

Worse: the switcher used `WlrKeyboardFocus.OnDemand`. Pick focused the chosen foot, then `shell.hide` unmapped the overlay and Hyprland restored keyboard focus to the window that had it when the overlay mapped — the same last foot. Address unchanged.

Hide also invokes plugin `close()`, which cancelled the cycle before `commitCycle` could read `cycleList`. The commit path has to capture the highlighted address before hide.

## In repo

- `WindowService.activate` restores if minimized, then `hl.dsp.focus`.
- `commitCycle` / `activateFromSwitcher` / inactive taskbar click call `activate`.
- Switcher `WlrKeyboardFocus.None`; card pick stashes `pendingActivate` and focuses after overlay hide.
- `omarchy-shell window commitCycle` captures the highlighted address, hides, then activates.
- Acceptance row 25 asserts `activewindow` changed. Pointer helper clicks the highlighted card center, not a hardcoded 896,540.

## Live evidence (2026-08-22, Hyprland 0.56.2, virtio-vga 1920×1080)

Not a go. Numbers from the running guest after this tranche.

- IPC `commitCycle`: active foot `0x56298316a300` → `0x56298351ec30`. `omarchy-task-switcher` unmapped.
- Absolute pointer card click at `896,540`: active `0x56298351ec30` → `0x56298316a300`. Overlay unmapped.
- Title-bar drag `[520,240]` → `[652,325]` (Δ132×85). Close at `1516,309` unmapped.

## Out of scope / still open

- Declaring W0 passed
- Peek / jump lists, quarter snap, multi-monitor
- hyprbars as a pacman package in the ISO mirror
- Tokyo Night, Nautilus-as-Files product, nvim-as-ordinary-text, TTY first-boot, ISO
