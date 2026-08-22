# W0 Tranche D — native minimize (in-place hide)

This is the worker slice after the Tranche C mouse lock. It is not a windowing go. Keep `eddd0b57` and `9d80ecd6`. Do not re-open `eddd0b57`. Do not re-bench `4ea1dcf3` + `a5b945da`.

Read with `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md`, `plans/desktop-mode-handoff.md`. Doctrine wins on conflict.

## Doctrine (this slice still obeys)

1. Zero-terminal ownership — minimize/restore are mouse and taskbar operations, not hyprctl.
2. Zero-hotkey-required — caption minimize still goes through `omarchy-shell window minimize`.
3. Windows muscle memory is an API — the window leaves the screen and comes back as the same window on the same workspace.
4. Visible before memorable — empty desktop vs restored client is the proof, not a JSON-only park.
5. Progressive disclosure — not this slice.
6. Consequential operations have state — hidden vs mapped is compositor state.
7. Recoverability — not this slice.

Overlay rule: Desktop Mode still must not rewrite `shell.json`.

Service rule: QML still calls `WindowService`; hyprbars still calls `omarchy-shell window …`. Minimize dispatch is `hl.plugin.omarchy_minimize.*`, not `bash -c`.

## Why this tranche

Jesse named the next gate that can actually move: native minimize, or hyprbars as a real package. Hyprland 0.56 still has no `hl.dsp.window.minimize`. `special:minimized` is a workspace move. `CWindow::setHidden` is the compositor hide used for swallow/xwayland; it is not exported as a dispatcher.

This slice exposes `setHidden` through a Hyprland plugin so the window stays on workspace `1` with `hidden: true`, then restores the same address in place.

hyprbars-as-package is not this slice. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.

## Root cause

`WindowService.minimize` dispatched `hl.dsp.window.move({ workspace = "special:minimized" })`. Identity held. A Windows minimize it is not: the client leaves the workspace.

`setHidden(true)` on a mapped client on a visible workspace skips `renderWindow` (`isHidden() && !standalone`). `hyprctl clients` reports `hidden: true` and keeps `workspace.id`. Restore is `setHidden(false)` plus `fullWindowFocus`. No workspace move.

Lua `HL.Window.hidden` is read-only. `hl.dsp.window.set_prop` does not set hidden. The plugin registers `hl.plugin.omarchy_minimize.minimize` / `restore` and returns `hl.dsp.no_op()` so `Hyprland.dispatch` can eval it.

## In repo

- `default/hypr/plugins/omarchy-minimize/` — plugin source + Makefile. Build on the Hyprland machine (`make && sudo make install`). ABI-pinned; hash mismatch refuses to load. Do not commit the `.so`.
- `default/hypr/desktop-windows.lua` loads `/usr/lib/hyprland-plugins/omarchy-minimize.so` (then `$OMARCHY_PATH/.../omarchy-minimize.so`) after hyprbars.
- `WindowService.minimize` / `restore` call the plugin. `minimized` is compositor `hidden`, not a workspace name.
- Acceptance `window_is_minimized` requires `hidden == true` and `workspace.name != "special:minimized"`. Restore requires `hidden != true` on the active workspace.

## Live evidence (2026-08-22, Hyprland 0.56.2, virtio-vga 1920×1080)

Not a go. Numbers from the running guest after this tranche.

- Plugin listed: `Plugin omarchy-minimize by Omarchy Ultimate` from `/usr/lib/hyprland-plugins/omarchy-minimize.so`.
- Four feet, all `hidden: true`, all `workspace: { id: 1, name: "1" }`. None on `special:minimized`. `mapped` stays true.
- Grim `all-hidden.png`: foot interior / title / close pixels are wallpaper `(17,17,17)`. Taskbar remains.
- Restore address `0x555bb2579650`: `hidden: false`, still workspace `1`, same `at`/`size`. Grim `one-restored.png`: foot interior `(35,35,35)`, close `(227,158,152)`.
- `omarchy-shell window minimize` / `restore` on three addresses: chosen restore unhides that address only; the other two stay hidden on workspace `1`.

## Out of scope / still open

- Declaring W0 passed
- hyprbars as a pacman package (still hyprpm cache `.so`)
- Alt+Tab address-change on this multi-pointer VM seat
- Tokyo Night, Nautilus, nvim, TTY first-boot, ISO
- Shipping a prebuilt `.so` in `omarchy-pkgs` / the ISO mirror
