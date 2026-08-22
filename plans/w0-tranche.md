# W0 Tranche B — work-area truth, compositor chrome, remembered float

This is the next Windowing Gate slice after the locked repair `4ea1dcf3` + `a5b945da`. It is not a product go. It exists to **move locked gates**, not to re-bench that writeup.

Read with `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md`, `plans/desktop-mode-handoff.md`. Doctrine wins on conflict.

## Doctrine (this slice still obeys)

1. Zero-terminal ownership — a user minimizes, snaps, and restores with the mouse, not hyprctl.
2. Zero-hotkey-required — caption buttons and taskbar are the path; Win+Arrow is an accelerator.
3. Windows muscle memory is an API — overlapping floats, caption min/max/close, snap halves, restore-to-normal.
4. Visible before memorable — compositor title bars with labeled hitboxes, not a hidden Super+drag ritual.
5. Progressive disclosure — no “edit this Lua file” to get a title bar.
6. Consequential operations have state — snap/max remember the previous rectangle and can return to it.
7. Recoverability — not this slice.

Overlay rule: Desktop Mode still must not rewrite `shell.json`.

Service rule: QML still calls `WindowService` verbs; hyprbars buttons call `omarchy-shell window …` (the same verbs), never interpolated `bash -c` around an address.

## Why this tranche, not theme / ISO / Dolphin

The reviewer lock left these W0-adjacent gates open:

- no compositor SSD (overlay captions are not SSD)
- minimize is still `special:minimized`
- snap still allowed 32px of slop (live 1054 vs 1040)
- no mouse proof
- Tokyo Night, Nautilus, nvim, TTY first-boot, no ISO (later product slices; **out of this tranche**)

Phase 1 is still the engineering gate. This tranche only touches windowing.

## Root-cause hypotheses (evidence before code)

### Snap height 1054 vs work area 1040

Live after LTRB: reserved `[0,0,0,40]`, taskbar `y=1040 h=40`, snap `960×1054`. `WindowModel.snapRect` on `{ width: 1920, height: 1080, reserved: [0,0,0,40] }` is `960×1040`. So the JS math is not the bug when fed compositor JSON.

`WindowService._monitorGeom()` prefers Quickshell `mon.width` / `mon.height` over `lastIpcObject`. The previous handoff told a later turn to do that because `lastIpcObject` can be stale after a mode change. Those Quickshell properties are a different box: `1080 - 26 = 1054` (two `gaps_out` of 10 plus border). Mixing that height with IPC reserved (or with empty reserved) produces exactly the live snap.

**Fix:** snap/maximize geometry uses compositor monitor JSON only (`lastIpcObject.width/height/reserved` after `refreshMonitors()`). If that JSON is missing, snap is a no-op with `lastError`, not a guessed size. Desktop Mode also zeros `gaps_in` / `gaps_out` so the floating path is not a tiling inset.

Harness slop drops from 32px to 8px (two 2px borders, not “whatever”).

### Overlay captions are not SSD

Hyprland 0.56 still has no core server-side decorations. It advertises xdg-decoration and gained CSD title-bar drags; terminals like `foot` have no CSD. The maintainable compositor decoration is **hyprbars** (`IHyprWindowDecoration`). Official install is hyprpm (ABI-pinned to the running Hyprland). There is an AUR `hyprland-plugin-hyprbars`; it is **not** a pacman repo package, so it must not go in `install/omarchy-other.packages`.

The overlay `omarchy.ultimate-window-chrome` layer sits on the client. That was a stand-in. This tranche **removes it** and loads hyprbars in Desktop Mode only. Two title bars would be a parallel structure; finish-it forbids that.

### Minimize

Hyprland 0.56 still has no native minimized state. The compositor API remains `special:minimized`. This tranche does **not** pretend otherwise and does **not** replace the compositor. Identity-preserving park/restore stays. The “Windows minimize” gate stays **open**. Caption minimize still goes through `WindowService.minimize`.

### Leftover half-screen “tile”

Desktop Mode already floats. The screenshot’s right-hand pane was a probe snap left at 50% width. This tranche gives new windows a default overlapping float (`880×560`) and remembers the pre-snap/pre-max rectangle so Win+Down / restore-normal unsnaps instead of looking tiled.

### Mouse proof

IPC green is not a mouse. hyprbars title bars are part of the window (`bar_part_of_window`), so pointer hit-testing is the compositor’s. Live proof is: plugin listed, overlay namespace gone, pointer click on the bar moves/maximizes/closes. Alt+Tab cards already have a click handler; live proof is a pointer click on a card, not `omarchy-shell window commitCycle`.

## In scope (must complete)

1. Compositor-only work area for snap/max.
2. Desktop Mode `gaps_in = 0`, `gaps_out = 0`.
3. Acceptance size/position slop **8px**, not 32px.
4. Default overlapping float size; remembered normal bounds; `restoreNormal` / Win+Down unsnap.
5. hyprbars loaded in Desktop Mode: min / max / close / double-click maximize, actions via `omarchy-shell window`.
6. Delete overlay caption plugin.
7. hyprbars comes from **hyprpm** (`hyprpm add https://github.com/hyprwm/hyprland-plugins` then `hyprpm enable hyprbars`). Do **not** put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages` — that file is pacman-only and the name is not in the repos (`omarchy-pkg-add` would fail the ISO). Desktop Mode loads `/var/cache/hyprpm/$USER/hyprland-plugins/hyprbars.so` and runs `hyprpm reload -n` on `hyprland.start`.
8. Tests: WindowModel geometry, desktop-windows hyprbars + gaps, no overlay plugin, tighter harness, hyprbars listed in session chrome.
9. Live guest: snap height matches work area within 8px; hyprbars loaded; overlay gone; default float is not a half-tile.

## Out of scope (do not “complete” by papering over)

- Declaring Windowing Gate W0 passed
- Replacing Hyprland
- Native minimize (not special workspace)
- Tokyo Night / design system / masterpiece Start
- Dolphin, nvim-as-txt, TTY first-boot, product ISO
- Quarter snap, snap chooser, multi-monitor matrix, Steam/Wine/Electron matrix

## Live evidence (2026-08-22, Hyprland 0.56.2, virtio-vga 1920×1080)

Not a go. Numbers from the running guest after this tranche, compositor JSON plus screenshots.

- Mode `desktop`. Taskbar `omarchy-taskbar` at `x=0 y=1040 w=1920 h=40`. Overlay namespace `omarchy-window-chrome` count **0**.
- Monitor reserved **`[0,0,0,40]`**. The earlier 173px ghost top reserved was the overlay caption exclusive zone; it went to zero when that plugin was deleted and the shell restarted. Work area is `1920×1040`.
- Gaps `general:gaps_out` / `gaps_in` are `0 0 0 0`.
- Default float: foot opens `880×560` at `[520,240]` (centered in the work area), `floating: true`. Two feet stack on the same rect — overlapping, not 50/50 tiles.
- Snap after hyprbars inset: left **`[0,32] 960×1008`**, right **`[960,32] 960×1008`**. hyprctl `at`/`size` is the client box; hyprbars (`bar_height=32`, `bar_part_of_window=true`) still draws **above** that box. Insetting 32px keeps the title bar on screen. Pixel check on `w0-snap2.png`: close-button red at left `(938–951, 9–22)` and right `(1898–1911, 9–22)`; client content starts at `y=32`. Within 8px of the intended halves.
- `restoreNormal` after a right snap returned the pre-snap rect **`[520,240] 880×560`** (remembered compositor client JSON, not `defaultFloatRect`).
- Maximize: `fullscreen: 1`, `[2,34] 1916×1004`. Occupied span bottom `34+1004=1038` vs work bottom 1040 (2px). hyprbars sits in the top ~32px of the work area.
- hyprbars plugin listed (`Plugin hyprbars by Vaxry`). Buttons are compositor decorations (red close measured on the floating window at `(1378–1391, 217–230)` with client `at.y=240`). Caption actions call `omarchy-shell window`.
- Minimize is still `special:minimized`. Identity restore still holds from the previous live pass; the Windows-minimize gate is still open.
- Mouse: compositor cursor can be placed on those hyprbars pixels (`hyprctl cursorpos` 960,224 on the bar, 1384,224 on the close button). `ydotool` BTN_LEFT, QEMU `mouse_button`, and VNC pointer clicks from this host did **not** move or close the window. The USB-tablet / uinput / VNC paths on this guest do not actuate hyprbars. That is a harness limit, not a mouse go. The mouse gate stays **open**.

## Success / still-open after this tranche

| Gate | After this tranche |
| --- | --- |
| 32px snap slop / 1054 vs 1040 | **Moved** — live halves are `[0,32] 960×1008` / `[960,32] 960×1008` on a `[0,0,0,40]` 1920×1080, matching the client box under hyprbars within 8px. The old 1054-vs-1040 mix of Quickshell height and IPC reserved is gone. |
| Overlay-as-SSD | **Moved** — hyprbars is loaded and draws title bars; overlay plugin is deleted and its layer is absent. |
| `special:minimized` | **Still open** (Hyprland has no native minimize) |
| Mouse proof | **Still open** — title bars are visible and aimed; this host could not actuate them. |
| Tokyo Night, Nautilus, nvim, TTY, ISO | Unchanged |

Do not ask for a product review until at least one of those locked gates actually moved in commits plus live evidence.
