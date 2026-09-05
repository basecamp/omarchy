# AGENTS.md

You are running on an Omarchy Linux system (Arch Linux + Hyprland Wayland compositor).

## Rules

- Never modify `/usr/share/omarchy/` — it's read-only and updates overwrite changes.
- Always use `~/.config/` for user configuration.
- Prefer the `omarchy` CLI for system tasks. Run `omarchy commands` to see what's available.
- Use `sudo` in a terminal for privileged commands. Use `pkexec` only when the agent cannot interact with a terminal for a password prompt.
- Run `omarchy debug --no-sudo --print` to gather system info — never bare `omarchy debug`.

## System map

- Window manager: Hyprland. Config: `~/.config/hypr/`
- Shell bar/notifications: Quickshell. Config: `~/.config/omarchy/shell.json`
- Terminals: Alacritty, Foot, Kitty, Ghostty. Config: `~/.config/<terminal>/`
- Themes: `omarchy theme set <name>`. Custom themes: `~/.config/omarchy/themes/`
- Keybindings: `~/.config/hypr/bindings.lua`. Cheatsheet: Super+K
- Packages: `omarchy pkg add <pkg>` (pacman), `omarchy pkg aur add <pkg>` (AUR)
