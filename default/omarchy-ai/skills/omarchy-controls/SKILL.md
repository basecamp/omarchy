---
name: omarchy-controls
description: >-
  Omarchy input and automation: keybindings, input devices, voice dictation,
  window rules, autostart, hooks. Triggers: keybindings, keyboard layout,
  mouse/trackpad, Voxtype, XCompose, window rules, autostart, gestures, hotkeys.
---

<sources>

| What | Read From |
|------|-----------|
| Default bindings | `cat ~/.local/share/omarchy/default/hypr/bindings/*.conf` |
| XCompose sequences | `cat ~/.local/share/omarchy/default/xcompose` |
| Window rules | `cat ~/.local/share/omarchy/default/hypr/windows.conf` |
| Autostart | `cat ~/.local/share/omarchy/default/hypr/autostart.conf` |

</sources>

<keybindings>

| File | Purpose |
|------|---------|
| `~/.config/hypr/bindings.conf` | User bindings (edit this) |
| `~/.local/share/omarchy/default/hypr/bindings/` | Defaults (READ only) |

Syntax:
```conf
bind = MODIFIERS, key, dispatcher, arguments
bindd = MODIFIERS, key, description, dispatcher, arguments
unbind = MODIFIERS, key
```

**Modifiers:** `SUPER`, `SHIFT`, `CTRL`, `ALT` (combine with space)

</keybindings>

<rebinding_protocol>

1. MUST check existing: `omarchy-menu-keybindings --print`
2. MUST add `unbind` BEFORE new `bind` if collision
3. SHOULD inform user what was previously bound

```conf
unbind = SUPER, F
bindd = SUPER, F, File manager, exec, nautilus
```

</rebinding_protocol>

<input>

Edit: `~/.config/hypr/input.conf`

List devices: `hyprctl devices`

</input>

<voxtype>

```bash
omarchy-voxtype-install   # Install
omarchy-voxtype-model     # Change model
omarchy-voxtype-config    # Edit config
```

Usage: Hold `SUPER + CTRL + X`, release to stop

Config: `~/.config/voxtype/config.toml`

</voxtype>

<xcompose>

Edit: `~/.XCompose`

See built-in: `cat ~/.local/share/omarchy/default/xcompose`

MUST restart after editing: `omarchy-restart-xcompose`

Compose key: Caps Lock

</xcompose>

<window_rules>

**Syntax varies by Hyprland version.** MUST fetch docs first:
https://github.com/hyprwm/hyprland-wiki/blob/main/content/Configuring/Window-Rules.md

</window_rules>

<autostart>

Edit: `~/.config/hypr/autostart.conf`

Reference: `cat ~/.local/share/omarchy/default/hypr/autostart.conf`

</autostart>

<hooks>

Location: `~/.config/omarchy/hooks/`

Available: `theme-set`, `font-set`, `post-update`

</hooks>

<toggles>

```bash
omarchy-toggle-idle        # Screen locking
omarchy-toggle-nightlight  # Blue light filter
omarchy-toggle-waybar      # Status bar
```

</toggles>
