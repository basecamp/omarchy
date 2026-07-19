---
name: omarchy
description: >
  REQUIRED for end-user customization of Linux desktop, window manager, or system config.
  Use when editing ~/.config/hypr/, ~/.config/omarchy/,
  ~/.config/alacritty/, ~/.config/foot/, ~/.config/kitty/, or ~/.config/ghostty/.
  Triggers: Hyprland, window rules, animations, keybindings, monitors, gaps, borders,
  blur, opacity, omarchy-shell, bar, terminal config, themes, background,
  night light, idle, lock screen, screenshots, reminders, layer rules, workspace
  settings, display config, and user-facing omarchy commands. Excludes Omarchy
  source development through `omarchy dev link` workflows.
---

# Omarchy Skill

Manage [Omarchy](https://omarchy.org/) Linux systems - a beautiful, modern, opinionated Arch Linux distribution with Hyprland.

This skill is for end-user customization on installed systems.
It is not for contributing to Omarchy source code.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/hypr/` (window rules, animations, keybindings, monitors, etc.)
- Editing `~/.config/omarchy/shell.json` (status bar layout, widgets)
- Editing terminal configs (alacritty, foot, kitty, ghostty)
- Editing ANY file in `~/.config/omarchy/`
- Window behavior, animations, opacity, blur, gaps, borders
- Layer rules, workspace settings, display/monitor configuration
- Themes, backgrounds, fonts, appearance changes
- User-facing `omarchy` commands (`omarchy theme ...`, `omarchy refresh ...`, `omarchy restart ...`, etc.)
- Screenshots, screen recording, reminders, night light, idle behavior, lock screen

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for Omarchy development tasks** (editing the Omarchy source tree, creating migrations, or running `omarchy dev ...` workflows).

## Critical Safety Rules

When an agent needs to trigger privileged work, use `pkexec` so Omarchy can
present a graphical prompt for the user to approve. Never invoke `sudo` from an
agent action, and do not wrap an `omarchy` command that already manages
privilege elevation itself.

**For end-user customization tasks, NEVER modify anything in `/usr/share/omarchy/`** - but READING is safe and encouraged.

On a normal installation, `$OMARCHY_PATH` points to `/usr/share/omarchy`, which
contains Omarchy's packaged runtime files. `omarchy dev link` can point
`$OMARCHY_PATH` at a source checkout instead; that is a development workflow
and is outside this skill's scope. Changes to the packaged directory will be:
- Lost on next `omarchy update`
- Overwritten by package updates
- Liable to break Omarchy's runtime or update mechanism

```
/usr/share/omarchy/     # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                    # Source scripts (symlinked to PATH)
├── config/                 # Default config templates
├── themes/                 # Stock themes
├── default/                # System defaults
├── shell/                  # Omarchy shell source and defaults
├── migrations/             # Update migrations
└── install/                # Installation scripts
```

**Reading `/usr/share/omarchy/` is SAFE and useful** - do it freely to:
- Understand how omarchy commands work: `omarchy theme set --help` or `sed -n '1,240p' "$(command -v omarchy-theme-set)"`
- See default configs before customizing: `cat "$OMARCHY_PATH/config/omarchy/shell.json"`
- Check stock theme files to copy for customization
- Find default Hyprland settings: `rg -n '<setting>' "$OMARCHY_PATH/default/hypr"`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/omarchy/themes/<custom-name>/` - Custom themes (must be real directories)
- `~/.config/omarchy/hooks/` - Custom automation hooks

If the request is to develop Omarchy itself, this skill is out of scope. Follow repository development instructions instead of this skill.

## Privilege Escalation

Use `pkexec` whenever an agent must trigger a privileged command. This gives the
user a graphical authorization prompt with command context. Never launch
`sudo` from an agent action. If an existing `omarchy` command manages elevation
itself, run it without either wrapper. If a workflow cannot safely use
`pkexec`, explain the command and let the user run the interactive `sudo` flow
themselves.

## System Architecture

Omarchy is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Arch Linux** | Base OS | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Omarchy shell** | Status bar + notifications (Quickshell) | `~/.config/omarchy/shell.json` |
| **Launcher/menu** | Quickshell launcher and Omarchy menu | `~/.config/omarchy/shell.json`, `~/.config/omarchy/extensions/omarchy-menu.jsonc` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Omarchy OSD** | On-screen display | Quickshell plugin |

## Command Discovery

Omarchy ships a single `omarchy` CLI that dispatches to all `omarchy-*` binaries via `omarchy <group> <action>`. Always prefer this form — it is self-documenting and stable. The underlying `omarchy-*` binaries still exist on `PATH` and remain safe to read for source.

```bash
# List every documented command and its summary
omarchy commands

# Show the commands inside a group
omarchy theme --help
omarchy refresh --help
omarchy restart --help

# Show help for a specific command (does not execute it)
omarchy theme set --help

# Machine-readable listing (binary, route, summary, args, aliases)
omarchy commands --json

# Read a command's source to understand it
sed -n '1,240p' "$(command -v omarchy-theme-set)"
```

### Command Groups

Run `omarchy --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `omarchy refresh` | Reset config to defaults (backs up first) | `omarchy refresh shell` |
| `omarchy restart` | Restart a service/app | `omarchy restart shell` |
| `omarchy toggle` | Toggle feature on/off | `omarchy toggle nightlight` |
| `omarchy theme` | Theme management | `omarchy theme set <name>` |
| `omarchy bar` | Configure bar layout and widgets | `omarchy bar plugin move omarchy.clock --section right` |
| `omarchy plugin` | Manage and clone shell plugins | `omarchy plugin clone omarchy.clock local.clock --replace` |
| `omarchy hook` | Install user automation hooks | `omarchy hook install theme-set ~/my-theme-hook` |
| `omarchy install` | Install optional software / packages | `omarchy install docker dbs` |
| `omarchy launch` | Launch apps | `omarchy launch browser` |
| `omarchy capture` | Screenshots and recordings | `omarchy capture screenshot` |
| `omarchy reminder` | Desktop notification reminders | `omarchy reminder 15 "Pickup Jack"` |
| `omarchy pkg` | Package management | `omarchy pkg add <pkg>` |
| `omarchy setup` | Initial setup tasks | `omarchy setup security fingerprint` |
| `omarchy update` | System updates | `omarchy update` |

## Configuration Locations

### Hyprland (Window Manager)

```
~/.config/hypr/
├── hyprland.lua       # Main config (loads Omarchy defaults and user overrides)
├── bindings.lua       # Keybindings
├── monitors.lua       # Display configuration
├── input.lua          # Keyboard/mouse settings
├── looknfeel.lua      # Appearance (gaps, borders, animations)
├── autostart.lua      # Startup applications
└── hyprsunset.conf    # Night light / blue light filter
```

Omarchy 4 uses Hyprland's Lua configuration. Before editing, inspect
`~/.config/hypr/hyprland.lua` and the required `hypr.*` modules to confirm the
active files. Do not edit legacy `.conf` copies when the Lua config is active;
Hyprland will reload cleanly while ignoring those inactive files.

**Key behaviors:**
- Hyprland auto-reloads on config save (no restart needed for most changes)
- Use `hyprctl reload` to force reload
- After ANY Hyprland config change, validate with `hyprctl reload` followed by `hyprctl configerrors`
- If `hyprctl configerrors` reports errors, address them and rerun validation until clean or until a real blocker is identified
- Use `omarchy refresh hyprland` to reset to defaults

### Omarchy shell (Status Bar + Notifications)

The bar, notification daemon, settings panel, and assorted overlays all run
inside a single long-running Quickshell process (`omarchy-shell`).

```
~/.config/omarchy/shell.json                    # User config: bar, plugins, idle timeouts
~/.config/omarchy/plugins/<plugin-id>/          # User-owned shell plugins
~/.config/omarchy/extensions/omarchy-menu.jsonc # User menu entries
$OMARCHY_PATH/config/omarchy/shell.json          # Canonical defaults
```

The shell hot-reloads `shell.json` on save — no restart needed for layout
changes. Once the user file exists it is canonical; Omarchy does not deep-merge
it with newer defaults. Prefer `omarchy bar ...` and `omarchy plugin ...`
commands for scriptable changes because they preserve the expected schema and
reload the shell configuration.

`idle.screensaver` and `idle.lock` in `shell.json` are seconds since user idle
began. If the lock value is earlier than the screensaver value, the system locks
before the screensaver would start.

First-party plugin code under `$OMARCHY_PATH/shell/plugins/` is read-only. To
customize a built-in plugin, clone it into the user plugin directory and replace
the existing instance, for example:

```bash
omarchy plugin clone omarchy.workspaces local.workspaces \
  --name "Custom Workspaces" --replace
# Edit ~/.config/omarchy/plugins/local.workspaces/, then:
omarchy plugin validate ~/.config/omarchy/plugins/local.workspaces
omarchy plugin rescan
```

Third-party plugins execute unsandboxed inside `omarchy-shell`. Review their
source before enabling them, and obtain user confirmation before installing,
updating, or removing one. Non-interactive invocations require `--yes`; passing
it confirms that the review and approval have already happened.

**Commands:** `omarchy restart shell`, `omarchy refresh shell`,
`omarchy plugin list`, `omarchy bar plugin --help`

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `omarchy restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |

## Safe Customization Patterns

### Pattern 1: Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/hypr/bindings.lua

# 2. Backup before changes
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Hyprland: auto-reloads on save, but MUST validate with `hyprctl reload` and `hyprctl configerrors`
# - Omarchy shell: shell.json hot-reloads; use `omarchy plugin rescan` for user plugin code changes
# - Omarchy menu extension JSONC: hot-reloads on save
# - Terminals: MUST restart with `omarchy restart terminal`
```

### Pattern 2: Make a new theme

1. Create `~/.config/omarchy/themes/<theme-slug>/`.
2. Inspect `$OMARCHY_PATH/themes/catppuccin/` and `$OMARCHY_PATH/docs/theming.md` for the current format.
3. Put theme-owned backgrounds in `~/.config/omarchy/themes/<theme-slug>/backgrounds/`. Background-only overrides may instead go in `~/.config/omarchy/backgrounds/<theme-slug>/`.
4. Apply it with `omarchy theme set <theme-slug>`; display names such as `Tokyo Night` are normalized to slugs such as `tokyo-night`.

### Pattern 3: Use Hooks for Automation

Install scripts into `~/.config/omarchy/hooks/<name>.d/` to run automatically
on events. The `.d` layout allows multiple independent hooks for the same
event. A legacy single script at `~/.config/omarchy/hooks/<name>` is also run,
but prefer the composable `.d` layout.

```bash
# Available hooks (see samples in ~/.config/omarchy/hooks/):
~/.config/omarchy/hooks/
├── battery-low.d/          # Low-battery warning (percentage in $1)
├── font-set.d/             # After font change (font family in $1)
├── post-boot.d/            # After the desktop starts
├── post-update.d/          # After `omarchy update`
├── pre-refresh-pacman.d/   # After pacman config refresh, before package sync
└── theme-set.d/            # After theme change (normalized theme slug in $1)
```

Example source hook (`~/my-theme-hook`):
```bash
#!/bin/bash
THEME_NAME=$1
echo "Theme changed to: $THEME_NAME"
# Add custom actions here
```

Install it with `omarchy hook install theme-set ~/my-theme-hook`. The command
copies it into `~/.config/omarchy/hooks/theme-set.d/` and makes it executable.

### Pattern 4: Customize a Built-in Shell Plugin

Never edit a built-in plugin below `$OMARCHY_PATH/shell/plugins/`. Clone it to
the user directory, edit the clone, validate it, and rescan:

```bash
omarchy plugin clone <built-in-id> <new-id> --replace
# Edit ~/.config/omarchy/plugins/<new-id>/
omarchy plugin validate ~/.config/omarchy/plugins/<new-id>
omarchy plugin rescan
```

Use `--replace` for an existing bar widget, `--add` to add another widget, or
`--use` when cloning a complete bar plugin. Run `omarchy plugin clone --help`
and `omarchy bar plugin --help` to confirm placement options.

### Pattern 5: Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
omarchy refresh shell
omarchy refresh hyprland

# Both commands back up each changed user file before copying its packaged default.
# `refresh shell` also restores bar defaults and restarts the shell.
# Hyprland detects the copied Lua config changes and reloads them.
```

## Common Tasks

### Themes

```bash
omarchy theme list              # Show available themes
omarchy theme current           # Show current theme
omarchy theme set <name>        # Apply theme; display names and normalized slugs both work
omarchy theme bg next           # Cycle background
omarchy theme install <url>     # Install from git repo
```

### Keybindings

Edit `~/.config/hypr/bindings.lua`. Quattro's defaults demonstrate the
canonical dispatcher forms:
```lua
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + W", "Close window", hl.dsp.window.close())
```

View current bindings: `omarchy menu keybindings --print`

**IMPORTANT: When re-binding an existing key:**

1. First check existing bindings: `omarchy menu keybindings --print`
2. If the key is already bound, you MUST call `hl.unbind(...)` BEFORE adding the replacement with `o.bind(...)`
3. Inform the user what the key was previously bound to

Example - rebinding SUPER+F (which is bound to fullscreen by default):
```lua
-- Unbind existing SUPER+F (was: fullscreen)
hl.unbind("SUPER + F")
-- New binding for file manager
o.bind("SUPER + F", "File manager", { omarchy = "nautilus" })
```

Always tell the user: "Note: SUPER+F was previously bound to fullscreen. I've added an `hl.unbind` call to override it."

### Display/Monitors

Edit `~/.config/hypr/monitors.lua`. Format:
```lua
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@144", position = "1920x0", scale = 1 })

-- Disable a monitor entirely.
hl.monitor({ output = "eDP-1", disabled = true })
```

List active and inactive monitors plus supported modes: `hyprctl monitors all`

### Window Rules

**CRITICAL: Hyprland window rules syntax changes frequently between versions.**

Before writing ANY window rules, you MUST fetch the current documentation from the official Hyprland wiki:
- https://wiki.hypr.land/Configuring/Window-Rules/

DO NOT rely on cached or memorized window rule syntax. The format has changed multiple times and using outdated syntax will cause errors or unexpected behavior.

Window rules go in `~/.config/hypr/hyprland.lua` or another required Lua
module. Prefer Omarchy's `o.window(match, rules)` helper when it represents the
needed rule, and always verify the current rule and match syntax from the wiki
first.

### Fonts

```bash
omarchy font list               # Available fonts
omarchy font current            # Current font
omarchy font set <name>         # Change font
```

### System

```bash
omarchy update                  # Full system update
omarchy version                 # Show Omarchy version
omarchy debug --no-sudo --print # Debug info (ALWAYS use these flags)
omarchy system lock             # Lock screen
omarchy system shutdown         # Shutdown
omarchy system reboot           # Reboot
```

**IMPORTANT:** Agents and non-interactive callers must run `omarchy debug` with
`--no-sudo --print` to avoid sudo and menu prompts. If the user wants an upload,
have them run plain `omarchy debug` in a visible interactive terminal and choose
the upload action. Do not use hidden internal upload commands.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
omarchy debug --no-sudo --print

# Interactive support flow (run in a visible terminal; offers upload/view/save)
omarchy debug

# Reset specific config to defaults
omarchy refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `omarchy refresh config hypr/hyprland.lua` will refresh ~/.config/hypr/hyprland.lua
omarchy refresh config <config-file>

# Full reinstall of configs (nuclear option)
omarchy reinstall
```

## Decision Framework

When user requests system changes:

1. **Is it a stock omarchy command?** Use it directly
2. **Is it a config edit?** Edit in `~/.config/`, never `/usr/share/omarchy/`
3. **Is it a theme customization?** Create a NEW custom theme directory
4. **Is it automation?** Use `omarchy hook install` and the hook `.d` directories
5. **Is it a package install?** Use `omarchy pkg add <pkgs...>` (or `omarchy pkg aur add <pkgs...>` for AUR-only packages)
6. **Is it built-in shell/plugin code?** Clone it with `omarchy plugin clone`; never edit the packaged copy
7. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)

### Reminder Requests

When the user asks to set a reminder, use `omarchy reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder 60 "Check laundry"
omarchy reminder show
omarchy reminder clear
```

## Out of Scope

This skill intentionally does not cover Omarchy source development. Do not use this skill for:
- Editing files in `/usr/share/omarchy/` (`bin/`, `config/`, `default/`, `shell/`, `themes/`, `migrations/`, etc.)
- Creating or editing migrations
- Running `omarchy dev ...` commands

## Example Requests

- "Change my theme to catppuccin" -> `omarchy theme set catppuccin`
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings, call `hl.unbind` if needed, then use `o.bind("SUPER + E", "File manager", { omarchy = "nautilus" })`
- "Configure my external monitor" -> Edit `~/.config/hypr/monitors.lua`
- "Make the window gaps smaller" -> Edit `~/.config/hypr/looknfeel.lua`
- "Set up night light to turn on at sunset" -> `omarchy toggle nightlight` or edit `~/.config/hypr/hyprsunset.conf`
- "Set a reminder to pickup jack in 15 minutes" -> `omarchy reminder 15 "Pickup Jack"`
- "Show my reminders" -> `omarchy reminder show`
- "Clear all reminders" -> `omarchy reminder clear`
- "Customize the catppuccin theme colors" -> Create `~/.config/omarchy/themes/catppuccin-custom/` by copying from stock, then edit
- "Run a script every time I change themes" -> Install it with `omarchy hook install theme-set <script>`
- "Change how workspace labels are rendered" -> Clone `omarchy.workspaces` to a user plugin with `--replace`, then edit the clone
- "Lock after ten minutes" -> Set `idle.lock` to `600` in `~/.config/omarchy/shell.json`
- "Reset shell/bar to defaults" -> `omarchy refresh shell`
