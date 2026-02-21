---
name: omarchy-theme
description: >-
  Omarchy visual theming: themes, waybar, colors, backgrounds, fonts, animations.
  Triggers: theme creation, waybar styling, color schemes, wallpapers, fonts,
  animations, gaps, borders, blur, opacity, hyprlock, notifications, launcher.
---

<sources>

| What | Read From |
|------|-----------|
| Stock themes | `ls ~/.local/share/omarchy/themes/` |
| Theme structure | `ls ~/.local/share/omarchy/themes/catppuccin/` |
| colors.toml format | `cat ~/.local/share/omarchy/themes/tokyo-night/colors.toml` |
| Template syntax | `cat ~/.local/share/omarchy/default/themed/waybar.css.tpl` |
| Theme set logic | `cat $(which omarchy-theme-set)` |

</sources>

<locations>

| Location | Purpose | Editable |
|----------|---------|----------|
| `~/.local/share/omarchy/themes/` | Stock | NO (READ only) |
| `~/.config/omarchy/themes/<name>/` | Custom | YES |
| `~/.config/omarchy/current/theme/` | Active | NO (generated) |

</locations>

<commands>

```bash
omarchy-theme-list
omarchy-theme-current
omarchy-theme-set <name>
omarchy-theme-bg-next
omarchy-theme-install <url>
```

</commands>

<custom_themes>

Required structure:
```
~/.config/omarchy/themes/<name>/
├── colors.toml       # Copy from stock theme, modify
├── backgrounds/      # Numbered: 1-*.png, 2-*.jpg
└── preview.png       # For theme selector
```

To see required variables: `cat ~/.local/share/omarchy/themes/tokyo-night/colors.toml`

</custom_themes>

<template_vars>

| Syntax | Output |
|--------|--------|
| `{{ variable }}` | `#7aa2f7` |
| `{{ variable_strip }}` | `7aa2f7` |
| `{{ variable_rgb }}` | `122,162,247` |

</template_vars>

<looknfeel>

Edit: `~/.config/hypr/looknfeel.conf`

Reference: `cat ~/.local/share/omarchy/config/hypr/looknfeel.conf`

</looknfeel>

<waybar>

- Config: `~/.config/waybar/config.jsonc`
- Styles: `~/.config/waybar/style.css`
- MUST restart after changes: `omarchy-restart-waybar`

</waybar>

<fonts>

```bash
omarchy-font-list
omarchy-font-current
omarchy-font-set <name>
```

</fonts>

<hooks>

Create: `~/.config/omarchy/hooks/theme-set`
```bash
#!/bin/bash
THEME=$1
# runs after theme change
```

</hooks>
