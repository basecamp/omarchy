# Omarchy Agent Operations Guide

<philosophy>

**Configurators, not developers.** Desktop usage, themes, packages, system tweaks. Help users, not build Omarchy.

</philosophy>

<safety>

<constraints>

- MUST NOT modify `~/.local/share/omarchy/` — READ only, git-managed
- MUST verify state before modifying
- MUST NOT revert user changes without asking
- SHOULD confirm before destructive commands (`rm`, `git reset`, `omarchy-refresh-*`)

</constraints>

<paths>

| Path | Editable |
|------|----------|
| `~/.local/share/omarchy/` | NO (READ only) |
| `~/.config/` | YES |
| `~/.config/omarchy/themes/` | YES |
| `~/.config/omarchy/hooks/` | YES |

</paths>

</safety>

<workflow>

1. **Assess** — Read files/state before modifying
2. **Plan** — Multi-step operations need planning tools
3. **Execute** — Minimal changes, follow conventions
4. **Validate** — `shellcheck`, `shfmt`, restart services
5. **Report** — Summarize changes, suggest next steps

</workflow>

<commands>

<discovery>

```bash
compgen -c | grep -E '^omarchy-' | sort -u    # List all
compgen -c | grep -E '^omarchy-theme'         # By prefix
cat $(which omarchy-theme-set)                 # Read source
```

</discovery>

<prefixes>

| Prefix | Purpose |
|--------|---------|
| `restart-*` | Restart service, keep config |
| `refresh-*` | Reset to defaults — MUST ask user first |
| `toggle-*` | Toggle feature |
| `theme-*` | Theme management |
| `pkg-*` | Package management |
| `launch-*` | Launch apps |
| `install-*` | Optional software |
| `update-*` | System updates |
| `cmd-*` | System commands (screenshot, shutdown, etc.) |
| `setup-*` | Hardware wizards (fingerprint, fido2, dns) |
| `dev-*` | Developer tools |
| `voxtype-*` | Voice dictation |
| `font-*` | Font management |
| `hyprland-*` | Window operations |
| `hibernation-*` | Power management |
| `reinstall-*` | Reinstall components |
| `webapp-*` | Web apps |
| `version-*` | Version queries |

</prefixes>

<key_commands>

| Command | Purpose |
|---------|---------|
| `omarchy-update` | Apply upstream updates |
| `omarchy-debug --no-sudo --print` | Debug info — MUST use these flags |
| `omarchy-theme-set <name>` | Change theme |
| `omarchy-menu-keybindings --print` | Show keybindings |

</key_commands>

</commands>

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
~/.local/share/omarchy/     # READ-ONLY
├── bin/                    # Commands
├── config/                 # Templates
├── themes/                 # Stock themes
├── default/                # Defaults
└── migrations/             # Updates

~/.config/                  # SAFE to edit
├── hypr/
│   ├── hyprland.conf       # Main
│   ├── bindings.conf       # Keys
│   ├── monitors.conf       # Displays
│   ├── input.conf          # Input
│   ├── looknfeel.conf      # Appearance
│   ├── autostart.conf      # Startup
│   ├── hypridle.conf       # Idle
│   ├── hyprlock.conf       # Lock
│   └── hyprsunset.conf     # Night light
├── waybar/
├── alacritty/
└── omarchy/                # Themes, hooks
```

</configs>

<themes>

Stock: `~/.local/share/omarchy/themes/`
Custom: `~/.config/omarchy/themes/<name>/`

<required_files>

```
<theme>/
├── colors.toml        # REQUIRED
├── backgrounds/       # 1-*.ext, 2-*.ext...
└── preview.png
```

</required_files>

<optional_files>

- `icons.theme` — GTK icons
- `neovim.lua` — Neovim config
- `vscode.json` — VSCode theme
- `btop.theme` — Btop colors
- `chromium.theme` — Browser chrome (RGB: `"210,196,219"`)
- `light.mode` — Empty = light GTK
- `hyprland.conf` — Border overrides

</optional_files>

<colors_toml>

```toml
accent = "#89b4fa"
background = "#1e1e2e"
foreground = "#cdd6f4"
cursor = "#f5e0dc"
selection_background = "#f5e0dc"
selection_foreground = "#1e1e2e"
active_border_color = "#CBA6F7"
color0 = "#45475a"   # through color15
```

</colors_toml>

Template overrides: `~/.config/omarchy/themed/*.tpl` overrides `default/themed/*.tpl`

Variables: `{{ var }}`, `{{ var_strip }}` (no #), `{{ var_rgb }}` (decimal)

</themes>

<hooks>

Location: `~/.config/omarchy/hooks/`
Activate: Remove `.sample` extension

| Hook | Trigger | Arg |
|------|---------|-----|
| `theme-set` | Theme change | `$1` = theme name (snake-case) |
| `font-set` | Font change | `$1` = font name |
| `post-update` | System update | None |

</hooks>

<keybindings>

Before rebinding:
1. MUST check: `omarchy-menu-keybindings --print`
2. MUST `unbind` before new `bind` if collision
3. SHOULD inform user of previous binding

```conf
unbind = SUPER, F
bindd = SUPER, F, File manager, exec, nautilus
```

</keybindings>

<window_rules>

Syntax varies by Hyprland version. MUST fetch docs first:
https://github.com/hyprwm/hyprland-wiki/blob/main/content/Configuring/Window-Rules.md

</window_rules>

<coding_style>

- Shell: `set -eEo pipefail`, 2-space indent, lowercase-hyphenated filenames
- Commands: `omarchy-<verb>-<noun>`
- Migrations: `omarchy-dev-add-migration --no-edit`
- Shell customization: `~/.bashrc` (preserved)

</coding_style>

<validation>

- SHOULD run `shellcheck` and `shfmt -i 2 -ci` on scripts
- MUST restart services if auto-reload unavailable
- SHOULD verify theme across: terminal, waybar, walker, mako, hyprlock
- Logs: `/var/log/omarchy-install.log`, `journalctl -u <service>`

</validation>

<troubleshooting>

```bash
omarchy-debug --no-sudo --print    # MUST use these flags
omarchy-upload-log install
omarchy-refresh-<app>              # MUST ask user first
```

| Issue | Fix |
|-------|-----|
| Display scaling | Check `GDK_SCALE` in hyprland.conf |
| Caps Lock | Compose key by default; remap in input.conf |
| Password lockout | `CTRL+ALT+F2` → `faillock --reset --user <name>` |

Docs: https://learn.omacom.io/2/the-omarchy-manual

</troubleshooting>

<security>

- Secrets: `~/.config/environment.d/*.conf` or session keyring
- MUST NOT bake secrets into templates
- SHOULD review third-party scripts with `bat`/`shellcheck`
- SHOULD confirm before destructive commands

</security>

<git>

- Commit style: Imperative (`refresh: align hyprland themes`)
- Default: `git pull --rebase`
- MUST NOT revert user changes without asking
- Dirty tree: modify only files for current work

</git>
