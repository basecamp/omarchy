# W0 Tranche E — hyprbars off the hyprpm cache

This is the worker slice after the Tranche D native-minimize lock. It is not a windowing go. Keep `eddd0b57` and `9d80ecd6`. Do not re-open `eddd0b57`. Do not re-bench `4ea1dcf3` + `a5b945da`.

Read with `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md`, `plans/desktop-mode-handoff.md`. Doctrine wins on conflict.

## Doctrine (this slice still obeys)

1. Zero-terminal ownership — title-bar chrome is a compositor plugin the install builds, not a hyprpm ritual the user runs.
2. Zero-hotkey-required — caption buttons still go through `omarchy-shell window`.
3. Windows muscle memory is an API — min/max/close stay on the window.
4. Visible before memorable — the title bar is still compositor SSD; this slice changes where the `.so` lives.
5. Progressive disclosure — not this slice.
6. Consequential operations have state — plugin load path is compositor state (`/proc/Hyprland/maps`).
7. Recoverability — not this slice.

Overlay rule: Desktop Mode still must not rewrite `shell.json`.

Service rule: QML still calls `WindowService`; hyprbars still calls `omarchy-shell window …`.

## Why this tranche

Jesse named the remaining gates that can actually move: native minimize (Tranche D), or hyprbars as a real package. `hyprland-plugin-hyprbars` is still AUR-only. `install/omarchy-other.packages` is pacman-only, so that name still must not go there.

The product defect was the runtime path: Desktop Mode loaded `/var/cache/hyprpm/$USER/hyprland-plugins/hyprbars.so` and ran `hyprpm reload -n` on start. A cache rebuild is not an installed compositor plugin.

This slice vendors hyprbars `v0.56.0` (`7644cecdb947060682891a0db2a0cdc5c0b9e704` — Hyprland 0.56.2 has no separate plugin tag), builds it with `omarchy-minimize` through `omarchy-apply-hyprland-plugins`, and installs both to `/usr/lib/hyprland-plugins/`. Desktop Mode loads only those paths.

This is not a pacman package in the ISO mirror. `omarchy-pkgs` is not in this checkout. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`.

## Root cause

hyprpm is a user cache compiler. The `.so` disappears when the cache is wiped, and ABI breaks when Hyprland upgrades without a rebuild. Official Arch extra still does not ship `hyprland-plugin-hyprbars`. The AUR name cannot be pacstrapped.

`CWindow` decorations already came from hyprbars. The missing piece was an install-time compile against the installed Hyprland headers, same as `omarchy-minimize`.

## In repo

- `default/hypr/plugins/hyprbars/` — vendored source, BSD-3, `UPSTREAM` pin, Makefile `install` into `/usr/lib/hyprland-plugins`. Do not commit the `.so`.
- `bin/omarchy-apply-hyprland-plugins` — hidden, requires sudo, builds hyprbars + omarchy-minimize. Fails if `OMARCHY_PATH` or `pkg-config hyprland` is missing.
- `install/config/hyprland-plugins.sh` — ISO `omarchy-apply-system` leaf.
- `default/hypr/desktop-windows.lua` loads `/usr/lib/hyprland-plugins/hyprbars.so` (then `$OMARCHY_PATH/.../hyprbars.so`). No hyprpm permission, cache path, or `hyprpm reload`.

## Live evidence (2026-08-22, Hyprland 0.56.2, virtio-vga 1920×1080)

Not a go. Numbers from the running guest after this tranche.

- `/proc/$(pgrep -n Hyprland)/maps` contains `/usr/lib/hyprland-plugins/hyprbars.so` and `/usr/lib/hyprland-plugins/omarchy-minimize.so`. No `/var/cache/hyprpm/` mapping.
- `hyprctl plugin list`: `Plugin hyprbars by Vaxry`, `Plugin omarchy-minimize by Omarchy Ultimate`.
- Overlay namespace `omarchy-window-chrome` absent. Taskbar layer `omarchy-taskbar` at `x=0 y=1040 w=1920 h=40`. Reserved `[0,0,0,40]`.
- Default float still `[520,240] 880×560`. Grim: wallpaper `(17,17,17)`, foot interior `(35,35,35)`, title `(27,27,27)`, close `(227,158,152)`.
- `omarchy-apply-hyprland-plugins` installed `hyprbars.so` 396864 bytes and `omarchy-minimize.so` 201768 bytes as root.

## Out of scope / still open

- Declaring W0 passed
- Shipping these `.so` files as a pacman package in `omarchy-pkgs` / the ISO mirror
- Putting `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`
- Alt+Tab address-change on this multi-pointer VM seat
- Tokyo Night, Nautilus, nvim, TTY first-boot, ISO
