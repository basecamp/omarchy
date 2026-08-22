# W0 Tranche C — real pointer proof

Keep `eddd0b57` and `9d80ecd6`. Do not re-open `eddd0b57`. Do not re-bench `4ea1dcf3` + `a5b945da`. This is not a windowing go. Bench stays idle.

Locked. HEAD is still `eddd0b57`. The dirty tree is a harness and cycle cleanup on top of Tranche B, not a new product SHA.

What actually moved: hyprbars is hittable with an absolute USB-tablet-class pointer. Relative ydotool was the wrong seat. Close at `1384,224` then `1516,309` unmapped the foot. Title-bar drag `[520,240]` → `[652,325]` (Δ132×85). Overlay chrome is still gone (layer count 0). That is compositor chrome, not “hyprbars ignores clicks.” 32px is bar-height inset, not snap slop.

What did not move: Alt+Tab address-change is not a held number. One painted-card click hid the overlay; that is not activate-the-other-foot. Do not treat the helper’s address-change assert as proven on this multi-pointer VM seat. Minimize is still `special:minimized`. hyprbars is still a hyprpm cache `.so`. Theme, Nautilus, nvim, TTY, ISO did not move.

The uncommitted helper is honest: missing `/dev/uinput` fails, it does not skip. `windows-native-test.sh` runs it. Alt+Tab in the harness is summon + screenshot, not `commitCycle` as the mouse proof. `cancelCycle` on overlay hide is correct. Cards are 120×120.

Next gate that can actually move is native minimize, or hyprbars as a real package. Stay idle until one of those lands.

Read with `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md`, `plans/desktop-mode-handoff.md`. Doctrine wins on conflict.

## Doctrine (this slice still obeys)

1. Zero-terminal ownership — minimize/snap/close are mouse operations, not hyprctl.
2. Zero-hotkey-required — caption buttons and Alt+Tab cards are the path.
3. Windows muscle memory is an API — title-bar drag, caption close, clickable Alt+Tab.
4. Visible before memorable — hyprbars is already on screen; this slice proves it is hittable.
5. Progressive disclosure — not this slice.
6. Consequential operations have state — close and activate have visible results.
7. Recoverability — not this slice.

Overlay rule: Desktop Mode still must not rewrite `shell.json`.

Service rule: QML still calls `WindowService`; hyprbars still calls `omarchy-shell window …`.

## Why this tranche

Tranche B moved overlay-as-SSD and the 1054-vs-1040 snap mix. Locked open after that review:

- mouse clicks on the measured close button are unproven
- minimize is still `special:minimized`
- hyprbars is a hyprpm cache `.so`, not `omarchy-other.packages`
- theme / Nautilus / nvim / TTY / ISO

Minimize cannot move without replacing Hyprland. hyprbars-as-pacman is locked out (`omarchy-other.packages` is pacman-only). Theme/ISO stay later slices.

The remaining W0 gate that can move is **mouse proof**. Doctrine rule 2 is the reason it comes next.

## Root cause (evidence)

ydotool is a relative uinput mouse. With QEMU usb-tablet + PS/2 also seated, `hyprctl cursorpos` follows ydotool motion while buttons stay on another device. Interior typing into an already-focused foot is not a click proof. Overlay layer count is 0; hyprbars `inputIsValid` is not being blocked by Quickshell.

An absolute uinput pointer (same class as the USB tablet) at the measured close button unmaps the aimed foot. The same device press-drags the title bar.

HMP `mouse_move` is relative. Host SendInput without grab does not move the guest cursor. VNC does not move Hyprland's cursor. Do not treat those as hyprbars misses.

## Live numbers (1920×1080, reserved `[0,0,0,40]`, hyprbars 32px above the client box)

- Close button red pixels were `1378–1391, 217–230` with foot `[520,240] 880×560`. ABS click at `1384,224` unmapped that client. After a 132×85 drag, close aim `1516,309` unmapped again (empty desktop, cursor on the close pixel).
- Title-bar drag: `at` `[520,240]` → `[652,325]`, delta **132×85** (harness slop is 8px).
- Alt+Tab overlay maps `omarchy-task-switcher` at `0,0 1920×1080`. Cards paint after ~1s (not at the instant the layer appears in JSON). `Switcher.qml` `MouseArea` calls `activateFromSwitcher`, not the keyboard commit. Closing the overlay calls `cancelCycle` so a leftover cycle does not skip the next highlight. Isolated ABS click on a painted card unmapped the overlay once. A repeatable address-change click is still the part of this gate the multi-pointer VM seat does not hold; the acceptance helper fails that path instead of skip-passing.

## In repo

- `test/acceptance.d/hyprbars-pointer-proof.py` — one ABS pointer; missing `/dev/uinput` is a failure, not a skip. Relative ydotool is not this gate.
- `test/acceptance.d/windows-native-test.sh` runs that helper. Alt+Tab summon still screenshots the overlay; activation is the pointer helper.

## Out of scope / still open

- Declaring W0 passed
- Native minimize (`special:minimized`)
- Putting `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`
- Tokyo Night, Nautilus, nvim, TTY first-boot, ISO
