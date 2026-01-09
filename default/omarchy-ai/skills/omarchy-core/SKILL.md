---
name: omarchy-core
description: >-
  Core Omarchy skill. REQUIRED for ANY desktop, window manager, or system config.
  Triggers: ~/.config/hypr/, ~/.config/waybar/, ~/.config/walker/, terminals,
  ~/.config/mako/, ~/.config/omarchy/, themes, keybindings, monitors, window rules,
  animations, any omarchy-* command.
---

<safety>

MUST NOT modify `~/.local/share/omarchy/` — READ freely, WRITE never.

- Git-managed; changes lost on `omarchy-update`
- Read to understand: `cat $(which omarchy-theme-set)`

Safe locations:
- `~/.config/` — User configuration
- `~/.config/omarchy/themes/<name>/` — Custom themes
- `~/.config/omarchy/hooks/` — Automation hooks

</safety>

<sources>

| What | Read From |
|------|-----------|
| All commands | `compgen -c \| grep -E '^omarchy-'` |
| Command source | `cat $(which omarchy-<cmd>)` |
| Default configs | `~/.local/share/omarchy/config/` |
| Stock themes | `~/.local/share/omarchy/themes/` |
| System defaults | `~/.local/share/omarchy/default/` |

</sources>

<restarts>

| Component | Auto-reload | Restart |
|-----------|-------------|---------|
| Hyprland | YES | `hyprctl reload` |
| Waybar | NO | `omarchy-restart-waybar` |
| Walker | NO | `omarchy-restart-walker` |
| Terminals | NO | `omarchy-restart-terminal` |
| Mako | NO | `omarchy-restart-mako` |
| Hypridle | NO | `omarchy-restart-hypridle` |

</restarts>

<configs>

```
~/.config/hypr/
├── hyprland.conf      # Main (sources others)
├── bindings.conf      # Keybindings
├── monitors.conf      # Displays
├── input.conf         # Keyboard/mouse
├── looknfeel.conf     # Gaps, borders, animations
├── autostart.conf     # Startup apps
├── hypridle.conf      # Idle behavior
├── hyprlock.conf      # Lock screen
└── hyprsunset.conf    # Night light
```

</configs>

<decisions>

1. **Command exists?** → Use it: `compgen -c | grep omarchy-<verb>`
2. **Config edit?** → Edit `~/.config/`, MUST NOT touch `~/.local/share/omarchy/`
3. **Custom theme?** → Create `~/.config/omarchy/themes/<name>/`
4. **Automation?** → Use `~/.config/omarchy/hooks/`
5. **Package?** → `yay` or `omarchy-pkg-add`

</decisions>

<warnings>

**Window Rules:** Syntax varies by Hyprland version. MUST fetch docs:
https://github.com/hyprwm/hyprland-wiki/blob/main/content/Configuring/Window-Rules.md

**Refresh vs Restart:**
| Command | Effect |
|---------|--------|
| `omarchy-restart-*` | Restart service, keep config |
| `omarchy-refresh-*` | Reset to defaults — MUST ask user first |

</warnings>

<debug>

```bash
omarchy-debug --no-sudo --print   # MUST use these flags
omarchy-upload-log install        # Share logs
```

</debug>
