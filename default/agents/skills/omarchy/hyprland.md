# Hyprland Configuration

Read this before changing keybindings, monitors, window rules, or any other
Hyprland (window manager) configuration.

Omarchy configures Hyprland in Lua. User files are loaded after Omarchy's
defaults, so overrides go here:

```
~/.config/hypr/
├── hyprland.lua       # Main config (loads Omarchy defaults, then user files)
├── bindings.lua       # Keybindings
├── monitors.lua       # Display configuration
├── input.lua          # Keyboard/mouse settings
├── looknfeel.lua      # Appearance (gaps, borders, animations)
├── autostart.lua      # Startup applications
├── hyprsunset.conf    # Night light / blue light filter
└── xdph.conf          # Screen sharing / desktop portal
```

**Key behaviors (the `.lua` files):**
- Hyprland auto-reloads on config save (no restart needed for most changes)
- Use `hyprctl reload` to force reload
- After ANY Hyprland Lua config change, validate with `hyprctl reload` followed by `hyprctl configerrors`
- If `hyprctl configerrors` reports errors, address them and rerun validation until clean or until a real blocker is identified
- Use `omarchy refresh hyprland` to reset the Lua config files to defaults

The two `.conf` files are read by separate processes, so `hyprctl` neither
applies nor validates them:
- `hyprsunset.conf` (night light): apply changes with `omarchy restart hyprsunset`; reset with `omarchy refresh hyprsunset`
- `xdph.conf` (screen-sharing portal): applies when the portal restarts, e.g. on next login

## Keybindings

Edit `~/.config/hypr/bindings.lua`. Format:
```lua
o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")
o.bind("SUPER + B", "Browser", { launch = "chromium" })  -- launch wraps with uwsm-app
```

View current bindings: `omarchy menu keybindings --print`

**IMPORTANT: When re-binding an existing key:**

1. First check existing bindings: `omarchy menu keybindings --print`
2. If the key is already bound, you MUST call `hl.unbind(...)` BEFORE the new `o.bind(...)`
3. Inform the user what the key was previously bound to

Example - rebinding SUPER+F (which is bound to fullscreen by default):
```lua
-- Unbind existing SUPER+F (was: fullscreen)
hl.unbind("SUPER + F")
-- New binding for file manager
o.bind("SUPER + F", "File manager", { launch = "nautilus" })
```

Always tell the user: "Note: SUPER+F was previously bound to fullscreen. I've added an unbind to override it."

## Display/Monitors

Edit `~/.config/hypr/monitors.lua`. Format:
```lua
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@144", position = "1920x0", scale = 1 })
```

List monitors and supported modes: `hyprctl monitors all`

## Window Rules

**CRITICAL: Hyprland window rules syntax changes frequently between versions.**

Before writing ANY window rules, you MUST fetch the current documentation from the official Hyprland wiki:
- https://wiki.hypr.land/Configuring/Basics/Window-Rules/

DO NOT rely on cached or memorized window rule syntax. The format has changed multiple times and using outdated syntax will cause errors or unexpected behavior.

Window rules go in `~/.config/hypr/hyprland.lua` or a required Lua module. Prefer Omarchy's `o.window(match, rules)` helper — see examples in `$OMARCHY_PATH/default/hypr/windows.lua`.
