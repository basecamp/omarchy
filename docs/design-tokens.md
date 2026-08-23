# Design Tokens

Project Ultimate's semantic token layer lives in `shell/Commons/Tokens.qml`, registered as the `qs.Commons.Tokens` singleton. It derives everything from the existing theme system (`Color.qml` palette + `Style.qml` structure), so all current theme packs keep working unchanged — a theme swap re-derives every token automatically.

First-party shell surfaces consume semantic tokens instead of arbitrary theme colors. That is how the whole operating system starts looking designed rather than themed. `themes/ultimate-light/` exists. Calling Tokens a "seed only" understates consumption: Start, Settings, TaskButton peek/menu, the task switcher, and the snap chooser already use `qs.Commons.Tokens`. The leak is chrome that bypasses the pipeline.

**Pipeline lock:** one token/theme pipeline must drive Superbar chrome **and** hyprbars caption chrome. Light theme must be able to propagate to both. New surfaces must not invent private hex palettes. Superbar `Taskbar.qml` pins `#1b1b1b` `#333333` `#3a3a3a` `#4a4a4a` `#e8943a` `#9cbc0d` `#55ffffff`. hyprbars pins `bar_color = "rgba(1a1a1acc)"` plus caption `rgb(c42b1c)` / `rgb(3d3d3d)` in `default/hypr/desktop-windows.lua`. Agent Fabric can proceed without waiting for the token unification; Phase 3 must not sprawl more one-off palettes.

## Token vocabulary

| Group | Tokens | Meaning |
|-------|--------|---------|
| `surface` | canvas, base, raised, glass, overlay | wallpaper/desktop backdrop; windows/pages/cards; elevated cards; Start/taskbar/transient flyouts; scrims |
| `text` | primary, secondary, disabled | text hierarchy |
| `accent` | primary, hover, pressed | interactive accent states |
| `border` | subtle, strong | hairline separation vs emphasized edges |
| `state` | success, warning, danger, info | status signaling (danger→urgent role today; dedicated theme keys arrive in Phase 2) |
| `radius` | small, medium, large | tiny controls; standard surfaces; major panels — derived from Hyprland rounding |
| `motion` | fast, normal | ~100 ms hover; ~200 ms panels/menus |

## Surfaces doctrine

Three principal surface levels: **Canvas** (wallpaper, main application background), **Surface** (windows, settings pages, cards), **Glass** (Start, taskbar, transient menus, flyouts, notifications, toasts). Glass is special — if everything is transparent, nothing feels special.

## Geometry

Modest corners, not pills: tiny controls 4–6, standard 8, large panel 12, major transient shell surface 14. Density ships in three modes later (compact / comfortable default / touch).

## Motion

Fast, causal, restrained: hover ~100 ms, menus ~150 ms, panels ~180–220 ms. Motion communicates causality; it does not perform. Reduced Motion disables it cleanly (accessibility phase).

## Extension path

When themes gain semantic overrides, tokens become overridable through the same `shell.toml` override machinery `Style.qml` already uses — consumers won't change.
