# DedSecOS

A Watch Dogs-inspired Linux distribution built on Arch Linux. Fork of [Omarchy](https://omarchy.org), fully rebranded with a DedSec hacker aesthetic -- neon green, electric cyan, near-black backgrounds, and a surveillance-console UI philosophy.

**Repo:** `VaheOfficial/DedMarchy`
**Base:** Arch Linux (rolling release)
**Compositor:** Hyprland (Wayland tiling)
**Install path:** `~/.local/share/omarchy`

---

## Installation

### Fresh Install (from Arch)

```bash
bash <(curl -sL https://raw.githubusercontent.com/VaheOfficial/DedMarchy/master/boot.sh)
```

Or clone and run locally:

```bash
git clone https://github.com/VaheOfficial/DedMarchy.git
cd DedMarchy
./install.sh
```

### Flags

| Flag | Description |
|------|-------------|
| `--blackarch` | Install curated BlackArch pentesting tools (~200-300 tools across 11 categories) |
| `--deploy-only` / `-d` | Copy files to `~/.local/share/omarchy` without running full install |

### Install Phases

1. **Preflight** -- Guard checks (vanilla Arch, not root, x86_64, Btrfs, Limine bootloader)
2. **Packaging** -- ~150 base packages, fonts, hardware-specific packages, EWW widgets, optional BlackArch tools
3. **Config** -- Theming, git, Docker, timezone, SSH, hardware fixes
4. **Login** -- greetd + DedSec greeter (replaces SDDM), Plymouth boot splash
5. **Post-install** -- Cleanup and reboot

---

## Boot Sequence

### Limine Bootloader
Custom branded bootloader config. Target OS name set to "DedSec".

### Plymouth Boot Splash
Script-based theme at `/usr/share/plymouth/themes/omarchy/`. Uses DedSec branding with `#050A0E` background and JetBrainsMono Nerd Font.

### DedSec Greeter (Login Screen)
A full QML/Quickshell-based login and lock screen replacing SDDM. Runs via `greetd` inside a minimal Hyprland session.

**Stack:** greetd + Hyprland + Quickshell + QML

**Components:**
- Animated splash screen ("DSEC" reveal animation)
- Identity card (operator ID derived from machine-id, access class from group membership)
- System status panel (hostname, node info)
- Terminal output simulation with system info
- Custom password field with blinking cursor
- Disclaimer bar ("Property of DedSec")

**Files:**
- QML project: `default/dedsec-greeter/` (deployed to `/opt/dedsec/`)
- Config: `/etc/dedsec/greeter.config.json` (auto-generated with real system info)
- Hyprland session: `/etc/dedsec/greeter.hyprland.conf`
- greetd config: `/etc/greetd/config.toml`

**Safety:** Falls back to SDDM if Quickshell is unavailable.

**Lock screen:** Same greeter in lockd mode. Triggered by `omarchy-lock-screen` (Super+Ctrl+L). Falls back to hyprlock.

---

## Desktop Environment

### Color Palette (DedSec Theme)

| Role | Color | Hex |
|------|-------|-----|
| Accent | Neon Green | `#00FF41` |
| Cyan | Electric Cyan | `#00E5FF` |
| Foreground | Pale Teal | `#B0F4E6` |
| Background | Near-Black | `#050A0E` |
| Surface | Dark Blue | `#0A1018` |
| Muted | Slate | `#1E3044` |
| Alert | Hot Magenta | `#FF2D6F` |
| Cursor | Bright Teal | `#C8FFF4` |

Full 16-color ANSI palette in `themes/dedsec/colors.toml`.

### Waybar (Top Bar)

Styled as a "data readout strip" -- no icons, pure text telemetry.

**Left:** `DSec` menu button | `[1 2 3 4 5]` workspaces | `// window_class`
**Center:** Screen recording indicator | Voxtype status | Update patch indicator
**Right:** `NET:ETH` | `VOL:85%` | `CPU:12%` | `MEM:34%` | `PWR:87%` | `14:58:03` | System tray

- `DSec` button opens the DedSec menu (or right-click for terminal)
- Active workspace in accent green, empty workspaces dimmed
- Dividers are subtle pipe characters
- Clock shows seconds, alt-click for full date

### EWW Desktop HUD

Persistent fullscreen overlay (non-focusable, desktop layer) providing ambient system info:

| Position | Widget | Update Interval |
|----------|--------|----------------|
| Top-right | `ENV // hostname` | 60s |
| Top-right | `NODE // ip_address` | 10s |
| Bottom-left | System log feed (last 5 entries) | 5s |
| Bottom-right | `KERNEL // 6.x.x` | 1hr |
| Bottom-right | `UPTIME // 2h 34m` | 30s |
| Center | `DEDSEC` watermark (5% opacity) | Static |

Config: `config/eww/eww.yuck` + `config/eww/eww.scss`

### Hyprland Animations

Snappy, decisive animations. No floaty effects.

- Window open/close: `popin 92%` with snappy bezier (~2.4-2.8 speed)
- Window close: instant timing
- Workspace switch: slide transition
- Fade in/out: nearly instant (~1.2 speed)
- Border: snappy 3-speed transition
- Active border: green-to-cyan gradient at 45 degrees
- Shadow: subtle green tint (`rgba(00FF4118)`)
- Blur: enabled (size 4, 3 passes) for frosted-glass terminals
- Rounding: 0 (sharp corners everywhere)

### Notifications (Mako)

- Position: top-right
- Font: JetBrainsMono Nerd Font 13px
- Border: 3px, accent green (from theme)
- Background: theme background
- Sharp corners (border-radius: 0)
- 5-second timeout (critical notifications persist)
- Spotify notifications suppressed
- Do-not-disturb mode supported

### Rofi (Launcher/Menu)

Two themes:
- `dedsec.rasi` -- System menu (northwest-anchored, 320px, used by `omarchy-menu`)
- `dedsec-drun.rasi` -- App launcher (centered, wider, used by Super+Space)

Visual: transparent dark background, green accent, left-border highlight on selection, monospace font.

---

## Keybindings

### Applications

| Shortcut | Action |
|----------|--------|
| `Super + Return` | Terminal |
| `Super + F` | File Manager |
| `Super + B` | Browser |
| `Super + M` | Music |
| `Super + N` | Neovim |
| `Super + T` | btop (system monitor) |
| `Super + D` | Lazy Docker |
| `Super + O` | Obsidian |
| `Super + /` | 1Password |
| `Super + K` | Show all keybindings |

### Menus

| Shortcut | Action |
|----------|--------|
| `Super + Space` | App launcher (rofi) |
| `Super + Alt + Space` | DedSec system menu |
| `Super + Escape` | System/power menu |

### Desktop

| Shortcut | Action |
|----------|--------|
| `Super + Shift + Space` | Toggle top bar |
| `Super + Ctrl + Space` | Next wallpaper |
| `Super + Shift + Ctrl + Space` | Theme menu |
| `Super + Backspace` | Toggle window transparency |
| `Super + Shift + Backspace` | Toggle workspace gaps |

### System

| Shortcut | Action |
|----------|--------|
| `Super + Ctrl + L` | Lock screen |
| `Super + Ctrl + W` | WiFi controls |
| `Super + Ctrl + A` | Audio controls |
| `Super + Ctrl + B` | Bluetooth controls |
| `Super + Ctrl + T` | Activity monitor (btop) |
| `Super + Ctrl + N` | Toggle nightlight |
| `Print` | Screenshot (with editor) |
| `Shift + Print` | Screenshot to clipboard |
| `Alt + Print` | Screen recording menu |
| `Super + Print` | Color picker |

### Notifications

| Shortcut | Action |
|----------|--------|
| `Super + ,` | Dismiss last |
| `Super + Shift + ,` | Dismiss all |
| `Super + Ctrl + ,` | Toggle do-not-disturb |

---

## DedSec Menu

Accessed via `Super + Alt + Space` or clicking `DSec` in the top bar. Rofi-based with nested submenus.

| Entry | Description |
|-------|-------------|
| **Launch** | Open app launcher (same as Super+Space) |
| **Intel** | Documentation links (keybindings, Hyprland wiki, Arch wiki, Neovim, Bash) |
| **Exploit** | Capture (screenshots, recording, color picker), Share, Toggle (nightlight, idle lock, top bar, Dead Signal), Hardware |
| **Arsenal** | BlackArch tool categories -- Recon, Scanner, Exploitation, Web App, Cracker, Wireless, Sniffer, Proxy, Forensic, Social, Fuzzer |
| **Skin** | Theme, Font, Background, Hyprland config, About |
| **Config** | Audio, WiFi, Bluetooth, Power, Sleep, Monitors, Keybindings, Input, DNS, Security |
| **Deploy** | Install services (JavaScript, PHP, Elixir, editors, terminals, AI, gaming) |
| **Purge** | Remove development tools |
| **Patch** | System updates, feed channel, config, hardware, password |
| **Ident** | System identity/about |
| **Shutdown** | Power menu |

---

## Terminal

### Shell Prompt (Starship)

Minimal green-on-dark prompt:
```
~/projects/myapp main +2 ! >>
```
- Directory: truncated to 2 levels, green
- Git branch: italic green
- Git status: ahead/behind/modified/untracked indicators
- Success: `>>` (bold green)
- Error: `!!` (bold red)

### Tmux

- Prefix: `Ctrl+Space` (also `Ctrl+b`)
- Status bar: top position
- Mouse: enabled
- Vi mode for copy
- Splits: `|` horizontal, `-` vertical (open in same directory)
- Navigation: `Ctrl+Shift+Arrows` (panes), `Ctrl+Alt+Arrows` (windows/sessions)

### Fastfetch

DedSec-branded system info display. Shows:
- Hardware: Host, CPU, GPU, Display, Disk, Memory, Swap
- Software: OS version, branch, channel, kernel, WM, terminal, packages, theme
- Status: OS age, uptime, update status

---

## Theming System

### Structure

```
themes/dedsec/
  colors.toml          # 16-color palette + accent/foreground/background
  backgrounds/         # Wallpapers
  btop.theme           # btop color scheme
  hyprland.conf        # Hyprland theme overrides
  icons.theme          # Icon theme selection
  neovim.lua           # Neovim base16 theme
  vscode.json          # VS Code theme
  vscode-extension/    # VS Code extension for theme
  waybar.css           # Waybar color variables
  preview.png          # Theme preview image
```

### Color Variables

Templates in `default/themed/*.tpl` use `{{ variable }}` placeholders:
- `{{ accent }}` -- raw color value (`#00FF41`)
- `{{ accent_strip }}` -- without `#` (`00FF41`)
- `{{ accent_rgb }}` -- RGB tuple (`0,255,65`)

Rendered by `omarchy-theme-set-templates` via sed substitution.

### Applying Themes

- `omarchy-theme-select` -- Interactive theme picker
- `omarchy-theme-bg-next` -- Cycle wallpapers
- `omarchy-refresh-*` -- Refresh individual component configs

---

## Security / Hacking Tools

### BlackArch Integration

Optional (`--blackarch` flag). Adds the BlackArch repository and installs curated tool groups:

| Category | Package Group |
|----------|--------------|
| Reconnaissance | `blackarch-recon` |
| Scanning | `blackarch-scanner` |
| Exploitation | `blackarch-exploitation` |
| Web Application | `blackarch-webapp` |
| Password Cracking | `blackarch-cracker` |
| Wireless | `blackarch-wireless` |
| Sniffing | `blackarch-sniffer` |
| Proxy | `blackarch-proxy` |
| Forensics | `blackarch-forensic` |
| Social Engineering | `blackarch-social` |
| Fuzzing | `blackarch-fuzzer` |

Full BlackArch install (~2800 tools, 50GB+) available via `omarchy-install-blackarch`.

### Firewall (UFW)

Configured on first boot:
- Default deny incoming, allow outgoing
- LocalSend ports (53317/tcp+udp) allowed
- Docker DNS routing configured
- `ufw-docker` integration installed

### Docker

Auto-enabled with:
- Log rotation (10MB max, 5 files)
- Host DNS resolver (172.17.0.1)
- User added to docker group (no sudo needed)
- Non-blocking boot (won't delay startup)

---

## System Configuration

### Managed Services

| Service | Status |
|---------|--------|
| greetd | Enabled (login manager) |
| Docker | Enabled |
| UFW | Enabled (first boot) |
| Bluetooth | Configured |
| CUPS (printing) | Configured |
| Avahi (mDNS) | Configured |
| systemd-resolved | Configured for Docker DNS |

### Hardware Support

Auto-detected and configured:
- NVIDIA (open/proprietary drivers, 580xx series)
- ASUS ROG (asusctl)
- Apple T2 MacBooks (SPI keyboard, audio, suspend fixes)
- Broadcom WiFi
- Surface keyboards
- Synaptic touchpads
- Various Ethernet adapters (yt6801)

### Migrations

Timestamped scripts in `migrations/`. Run automatically on update. Tracked via touch files in `~/.local/state/omarchy/migrations/`.

Create new migrations: `omarchy-dev-add-migration --no-edit`

---

## File Structure

```
DedMarchy/
  bin/                    # ~176 shell scripts (omarchy-* commands)
  boot.sh                 # Curl-based entry point
  install.sh              # Main installer
  install/
    preflight/            # Pre-install checks
    packaging/            # Package installation scripts
    config/               # System configuration scripts
    login/                # Login manager setup (greetd)
    post-install/         # Cleanup and reboot
    helpers/              # Error handling, logging, presentation
    omarchy-base.packages # Core pacman packages
    omarchy-other.packages# AUR/hardware packages
  config/                 # User configs (copied to ~/.config/)
    eww/                  # Desktop HUD widgets
    waybar/               # Top bar config
    starship.toml         # Shell prompt
    fastfetch/            # System info display
    tmux/                 # Terminal multiplexer
    rofi/                 # Launcher/menu themes
    btop/                 # System monitor
  default/
    hypr/                 # Hyprland config (modular)
    mako/                 # Notification daemon
    themed/               # Template files for theming
    plymouth/             # Boot splash
    limine/               # Bootloader config
    dedsec-greeter/       # QML greeter project
    eww/scripts/          # HUD helper scripts
  themes/
    dedsec/               # DedSec theme (default)
    gruvbox-material/     # (inherited from Omarchy)
    ...                   # Other themes
  migrations/             # Update migration scripts
```

---

## Development

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OMARCHY_PATH` | Install path (`~/.local/share/omarchy`) |
| `OMARCHY_INSTALL` | Install scripts path |
| `OMARCHY_MIRROR` | `edge` or `stable` |
| `OMARCHY_REF` | Git branch |
| `OMARCHY_BLACKARCH` | `1` to install BlackArch tools |

### Key Commands

| Command | Description |
|---------|-------------|
| `omarchy-refresh-hyprland` | Reload all Hyprland configs |
| `omarchy-refresh-greeter` | Update greeter files in /opt/dedsec/ |
| `omarchy-refresh-plymouth` | Update boot splash |
| `omarchy-refresh-limine` | Update bootloader config |
| `omarchy-theme-select` | Change theme |
| `omarchy-update` | System update |
| `omarchy-debug` | Generate debug info |
| `omarchy-install-blackarch` | Install BlackArch tools interactively |

### Code Style

- Two spaces for indentation, no tabs
- Bash `[[ ]]` syntax, not POSIX `[ ]`
- LF line endings (enforced by `.gitattributes`)
- All scripts prefixed with `omarchy-`

### Windows Development Note

The dev environment is Windows. `install.sh` includes a CRLF stripping step that converts all deployed files to LF line endings automatically. The `.gitattributes` file enforces `eol=lf` for all text files.
