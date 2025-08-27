#!/bin/bash

# Custom Omarchy Installation Script

if [[ "$1" != "--dry-run" && "$1" != "-n" ]]; then
  read -p "Do you want to run in dry run mode (shows what would happen without making changes)? (y/N): " -n 1 -r DRY_RUN_PROMPT
  echo
  if [[ $DRY_RUN_PROMPT =~ ^[Yy]$ ]]; then
    DRY_RUN=true
  fi
fi

# Exit immediately if a command exits with a non-zero status
set -eE

# Get the absolute path to the omarchy repository
OMARCHY_REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Omarchy repository directory: $OMARCHY_REPO_DIR"

# Setup path and variables
export PATH="$OMARCHY_REPO_DIR/bin:$HOME/.local/share/omarchy/bin:$PATH"
OMARCHY_INSTALL="$OMARCHY_REPO_DIR/install"

# Define helper functions for dry run mode
run_cmd() {
  if $DRY_RUN; then
    echo "[DRY RUN] Would execute: $*"
  else
    eval "$@"
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"
  local opts="$3"

  if $DRY_RUN; then
    echo "[DRY RUN] Would copy: $src -> $dest $opts"
  else
    cp $opts "$src" "$dest" 2>/dev/null || true
  fi
}

make_dir() {
  if $DRY_RUN; then
    echo "[DRY RUN] Would create directory: $1"
  else
    mkdir -p "$1"
  fi
}

create_link() {
  local target="$1"
  local link="$2"
  local opts="$3"

  if $DRY_RUN; then
    echo "[DRY RUN] Would create symlink: $target -> $link $opts"
  else
    ln $opts "$target" "$link" 2>/dev/null || true
  fi
}

remove_path() {
  if $DRY_RUN; then
    echo "[DRY RUN] Would remove: $1"
  else
    rm -rf "$1"
  fi
}

# Define package groups
REQUIRED_PACKAGES=(
  # Core Hyprland packages
  "hyprland"     # Core window manager
  "waybar"       # Status bar
  "wl-clipboard" # Clipboard utility

  # Hypr utility packages
  "hypridle"   # Idle daemon
  "hyprlock"   # Screen locking
  "hyprpicker" # Color picker
  "hyprshot"   # Screenshot utility
  "hyprsunset" # Night light utility

  # UI packages
  "mako"       # Notification daemon
  "swayosd"    # On-screen display
  "walker-bin" # App launcher
)

# Web app packages
WEB_APPS=(
  "figma"
  "zoom"
  "discord"
  "github"
  "youtube"
  "chatgpt"
  "google-contacts"
  "google-photos"
  "google-mail"
  "google-drive"
  "google-docs"
  "google-calendar"
  "whatsapp"
  "basecamp"
  "hey"
  "grok"
)

# Other optional packages
OTHER_OPTIONAL=(
  "obsidian" # Note-taking app
  "nvim"     # Neovim text editor
  "starship" # Shell prompt
)

# Function to create webapp desktop file
create_webapp() {
  local app_name="$1"
  local app_url="$2"
  local app_title="$3"

  make_dir ~/.local/share/applications

  if $DRY_RUN; then
    echo "[DRY RUN] Would create desktop shortcut for ${app_title} (${app_url}) at ~/.local/share/applications/${app_name}.desktop"
  else
    cat >~/.local/share/applications/"${app_name}.desktop" <<EOF
[Desktop Entry]
Name=${app_title}
Exec=omarchy-launch-webapp "${app_url}"
Icon=${app_name}
Type=Application
Categories=Network;WebApps;
StartupWMClass=${app_name}
EOF
    echo "Created desktop shortcut for ${app_title}"
  fi
}

echo "==== OMARCHY INSTALLATION STARTED ===="
echo

# PART 1: Create ~/.local/share/omarchy directory structure
echo "==== STEP 1: Creating omarchy directory structure ===="
make_dir ~/.local/share/omarchy
make_dir ~/.local/share/omarchy/bin
make_dir ~/.local/share/omarchy/config
make_dir ~/.local/share/omarchy/default
make_dir ~/.local/share/omarchy/install
make_dir ~/.local/share/omarchy/applications
make_dir ~/.local/share/omarchy/applications/icons
make_dir ~/.local/share/omarchy/applications/hidden
make_dir ~/.local/share/fonts

# Copy bin directory
echo "Copying bin directory..."
copy_file "$OMARCHY_REPO_DIR/bin/"* ~/.local/share/omarchy/bin/ "-R"

# Copy config directory
echo "Copying config directory..."
copy_file "$OMARCHY_REPO_DIR/config/"* ~/.local/share/omarchy/config/ "-R"

# Copy default directory
echo "Copying default directory..."
copy_file "$OMARCHY_REPO_DIR/default/"* ~/.local/share/omarchy/default/ "-R"

# Copy install directory
echo "Copying install directory..."
copy_file "$OMARCHY_REPO_DIR/install/"* ~/.local/share/omarchy/install/ "-R"

# Copy applications directory
echo "Copying applications directory..."
copy_file "$OMARCHY_REPO_DIR/applications/"* ~/.local/share/omarchy/applications/ "-R"

# Copy logo and other files
echo "Copying logo and other files..."
copy_file "$OMARCHY_REPO_DIR/logo.txt" ~/.local/share/omarchy/logo.txt
copy_file "$OMARCHY_REPO_DIR/logo.svg" ~/.local/share/omarchy/logo.svg
copy_file "$OMARCHY_REPO_DIR/icon.txt" ~/.local/share/omarchy/icon.txt

echo "Directory structure setup completed."
echo

# PART 2: Setup theme configuration
echo "==== STEP 2: Setting up theme configuration ===="

# Create necessary directories
make_dir ~/.config/omarchy/themes
make_dir ~/.config/omarchy/current
make_dir ~/.config/omarchy/branding

# Copy icon and logo files
copy_file "$OMARCHY_REPO_DIR/icon.txt" ~/.config/omarchy/branding/about.txt
copy_file "$OMARCHY_REPO_DIR/logo.txt" ~/.config/omarchy/branding/screensaver.txt

# Create symlinks for all themes
echo "Creating theme symlinks..."
for theme_dir in "$OMARCHY_REPO_DIR/themes/"*; do
  if [ -d "$theme_dir" ]; then
    theme_name=$(basename "$theme_dir")
    echo "  Linking theme: $theme_name"
    create_link "$theme_dir" ~/.config/omarchy/themes/ "-snf"
  fi
done

# Set Tokyo Night as the default theme
echo "Setting default theme to Tokyo Night..."
create_link ~/.config/omarchy/themes/tokyo-night ~/.config/omarchy/current/theme "-snf"

# Create a fallback hyprland.conf if it doesn't exist in the theme
if $DRY_RUN || [ ! -f ~/.config/omarchy/current/theme/hyprland.conf ]; then
  echo "Creating fallback hyprland.conf..."
  make_dir ~/.config/omarchy/current/theme

  if $DRY_RUN; then
    echo "[DRY RUN] Would create fallback hyprland.conf at ~/.config/omarchy/current/theme/hyprland.conf"
  else
    cat >~/.config/omarchy/current/theme/hyprland.conf <<'EOF'
# Omarchy default theme settings for Hyprland

# General theming
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)

    layout = dwindle
}

# Decoration theming
decoration {
    rounding = 10
    
    blur {
        enabled = true
        size = 3
        passes = 1
    }

    drop_shadow = true
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animation settings
animations {
    enabled = true

    bezier = myBezier, 0.05, 0.9, 0.1, 1.05

    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}
EOF
  fi
fi

echo "Theme configuration setup completed."
echo

# PART 3: Install packages
echo "==== STEP 3: Installing packages ===="

# Function to check if a package is installed
is_installed() {
  if $DRY_RUN; then
    return 1 # In dry run mode, pretend package is not installed
  else
    pacman -Q "$1" &>/dev/null
  fi
}

# Function to install packages that aren't already installed
install_if_missing() {
  local missing_packages=()

  for package in "$@"; do
    if ! is_installed "$package"; then
      missing_packages+=("$package")
    else
      echo "Package $package is already installed, skipping..."
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    if $DRY_RUN; then
      echo "[DRY RUN] Would install packages: ${missing_packages[*]}"
    else
      echo "Installing missing packages: ${missing_packages[*]}"
      sudo pacman -S --noconfirm --needed "${missing_packages[@]}"
    fi
  else
    echo "All packages in this group are already installed."
  fi
}

# Install required packages (no option to skip)
echo "Installing required packages..."
install_if_missing "${REQUIRED_PACKAGES[@]}"

# Ask about installing optional packages individually
echo
echo "==== Optional Packages Installation ===="
echo "Any packages not installed will require modifying it's associated keybind"
echo

# Install web apps
echo "Web Applications:"
WEBAPPS_TO_INSTALL=()

# Figma
read -p "Install Figma web app? (y/N): " -n 1 -r INSTALL_FIGMA
echo
if [[ $INSTALL_FIGMA =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("figma")
  create_webapp "figma" "https://www.figma.com" "Figma"
fi

# Zoom
read -p "Install Zoom web app? (y/N): " -n 1 -r INSTALL_ZOOM
echo
if [[ $INSTALL_ZOOM =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("zoom")
  create_webapp "zoom" "https://zoom.us/join" "Zoom"
fi

# Discord
read -p "Install Discord web app? (y/N): " -n 1 -r INSTALL_DISCORD
echo
if [[ $INSTALL_DISCORD =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("discord")
  create_webapp "discord" "https://discord.com/app" "Discord"
fi

# GitHub
read -p "Install GitHub web app? (y/N): " -n 1 -r INSTALL_GITHUB
echo
if [[ $INSTALL_GITHUB =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("github")
  create_webapp "github" "https://github.com" "GitHub"
fi

# YouTube
read -p "Install YouTube web app? (y/N): " -n 1 -r INSTALL_YOUTUBE
echo
if [[ $INSTALL_YOUTUBE =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("youtube")
  create_webapp "youtube" "https://youtube.com" "YouTube"
fi

# ChatGPT
read -p "Install ChatGPT web app? (y/N): " -n 1 -r INSTALL_CHATGPT
echo
if [[ $INSTALL_CHATGPT =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("chatgpt")
  create_webapp "chatgpt" "https://chat.openai.com" "ChatGPT"
fi

# Google Contacts
read -p "Install Google Contacts web app? (y/N): " -n 1 -r INSTALL_GCONTACTS
echo
if [[ $INSTALL_GCONTACTS =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-contacts")
  create_webapp "google-contacts" "https://contacts.google.com" "Google Contacts"
fi

# Google Photos
read -p "Install Google Photos web app? (y/N): " -n 1 -r INSTALL_GPHOTOS
echo
if [[ $INSTALL_GPHOTOS =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-photos")
  create_webapp "google-photos" "https://photos.google.com" "Google Photos"
fi

# Google Mail (Gmail)
read -p "Install Gmail web app? (y/N): " -n 1 -r INSTALL_GMAIL
echo
if [[ $INSTALL_GMAIL =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-mail")
  create_webapp "google-mail" "https://mail.google.com" "Gmail"
fi

# Google Drive
read -p "Install Google Drive web app? (y/N): " -n 1 -r INSTALL_GDRIVE
echo
if [[ $INSTALL_GDRIVE =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-drive")
  create_webapp "google-drive" "https://drive.google.com" "Google Drive"
fi

# Google Docs
read -p "Install Google Docs web app? (y/N): " -n 1 -r INSTALL_GDOCS
echo
if [[ $INSTALL_GDOCS =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-docs")
  create_webapp "google-docs" "https://docs.google.com" "Google Docs"
fi

# Google Calendar
read -p "Install Google Calendar web app? (y/N): " -n 1 -r INSTALL_GCALENDAR
echo
if [[ $INSTALL_GCALENDAR =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("google-calendar")
  create_webapp "google-calendar" "https://calendar.google.com" "Google Calendar"
fi

# WhatsApp
read -p "Install WhatsApp web app? (y/N): " -n 1 -r INSTALL_WHATSAPP
echo
if [[ $INSTALL_WHATSAPP =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("whatsapp")
  create_webapp "whatsapp" "https://web.whatsapp.com" "WhatsApp"
fi

# Basecamp
read -p "Install Basecamp web app? (y/N): " -n 1 -r INSTALL_BASECAMP
echo
if [[ $INSTALL_BASECAMP =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("basecamp")
  create_webapp "basecamp" "https://basecamp.com" "Basecamp"
fi

# Hey
read -p "Install Hey web app? (y/N): " -n 1 -r INSTALL_HEY
echo
if [[ $INSTALL_HEY =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("hey")
  create_webapp "hey" "https://app.hey.com" "Hey"
fi

# Grok
read -p "Install Grok web app? (y/N): " -n 1 -r INSTALL_GROK
echo
if [[ $INSTALL_GROK =~ ^[Yy]$ ]]; then
  WEBAPPS_TO_INSTALL+=("grok")
  create_webapp "grok" "https://grok.x.ai" "Grok"
fi

# Other optional packages
echo
echo "Other Optional Applications:"
OTHER_TO_INSTALL=()

# Obsidian
read -p "Install Obsidian? (y/N): " -n 1 -r INSTALL_OBSIDIAN
echo
if [[ $INSTALL_OBSIDIAN =~ ^[Yy]$ ]]; then
  OTHER_TO_INSTALL+=("obsidian")
  install_if_missing "obsidian"
fi

# Neovim
read -p "Install Neovim (nvim)? (y/N): " -n 1 -r INSTALL_NVIM
echo
if [[ $INSTALL_NVIM =~ ^[Yy]$ ]]; then
  OTHER_TO_INSTALL+=("nvim")
  install_if_missing "nvim"

  # Copy Neovim configuration if selected
  make_dir ~/.config/nvim
  copy_file ~/.local/share/omarchy/config/nvim ~/.config/ "-R"
  echo "Installed Neovim with configuration."
fi

# Starship prompt
read -p "Install Starship prompt? (y/N): " -n 1 -r INSTALL_STARSHIP
echo
if [[ $INSTALL_STARSHIP =~ ^[Yy]$ ]]; then
  OTHER_TO_INSTALL+=("starship")
  install_if_missing "starship"

  # Copy Starship configuration if selected
  copy_file ~/.local/share/omarchy/config/starship.toml ~/.config/
  echo "Installed Starship prompt with configuration."
fi

echo "Optional package installation completed."
echo

# PART 4: Install configuration files
echo "==== STEP 4: Installing configuration files ===="

# Copy over Omarchy configs
echo "Installing configuration files..."
make_dir ~/.config

# Remove existing Hyprland configs to ensure clean replacement
echo "Removing existing Hyprland configuration files..."
remove_path ~/.config/hypr
remove_path ~/.config/waybar
remove_path ~/.config/swayosd
remove_path ~/.config/walker
remove_path ~/.config/mako

# Required configs
echo "Installing core configuration files..."
copy_file ~/.local/share/omarchy/config/hypr ~/.config/ "-R"
copy_file ~/.local/share/omarchy/config/waybar ~/.config/ "-R"
copy_file ~/.local/share/omarchy/config/mako ~/.config/ "-R"
copy_file ~/.local/share/omarchy/config/swayosd ~/.config/ "-R"
copy_file ~/.local/share/omarchy/config/walker ~/.config/ "-R"

# Always copy environment configuration
copy_file ~/.local/share/omarchy/config/environment.d ~/.config/ "-R"

# Copy custom fonts
copy_file ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/

# Copy default bashrc from Omarchy if desired
read -p "Do you want to install the Omarchy default bashrc? (y/N): " -n 1 -r INSTALL_BASHRC
echo
if [[ $INSTALL_BASHRC =~ ^[Yy]$ ]]; then
  copy_file ~/.local/share/omarchy/default/bashrc ~/.bashrc
  echo "Installed default bashrc."
else
  echo "Skipping default bashrc installation."
fi

echo "Configuration files installed successfully!"
echo

# PART 5: Update system packages
read -p "Do you want to update system packages? (y/N): " -n 1 -r UPDATE_PACKAGES
echo
if [[ $UPDATE_PACKAGES =~ ^[Yy]$ ]]; then
  echo "==== STEP 5: Updating system packages ===="
  if $DRY_RUN; then
    echo "[DRY RUN] Would update package database with: sudo updatedb"
    echo "[DRY RUN] Would update system packages with: sudo pacman -Syu --noconfirm"
  else
    sudo updatedb 2>/dev/null || true
    sudo pacman -Syu --noconfirm
  fi
  echo "System packages updated."
else
  echo "Skipping system package updates."
fi
echo

# PART 6: Refresh services
echo "==== STEP 6: Refreshing services ===="
if $DRY_RUN; then
  echo "[DRY RUN] Would refresh Hyprland configuration"
  echo "[DRY RUN] Would refresh Waybar configuration"
  echo "[DRY RUN] Would refresh SwayOSD configuration"
  echo "[DRY RUN] Would refresh Hypridle configuration"
  echo "[DRY RUN] Would refresh Hyprlock configuration"
  echo "[DRY RUN] Would refresh Hyprsunset configuration"
  echo "[DRY RUN] Would refresh Walker configuration"
elif [ -f "$HOME/.local/share/omarchy/bin/omarchy-refresh-hyprland" ]; then
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-hyprland" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-waybar" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-swayosd" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-hypridle" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-hyprlock" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-hyprsunset" 2>/dev/null || true
  "$HOME/.local/share/omarchy/bin/omarchy-refresh-walker" 2>/dev/null || true
fi

echo "All services refreshed."
echo

# PART 7: Complete installation
echo "==== OMARCHY INSTALLATION COMPLETED ===="
if $DRY_RUN; then
  echo "Dry run completed. No changes were made to your system."
  echo "To perform the actual installation, run this script without the --dry-run option."
else
  echo "Omarchy has been successfully installed!"
fi
echo

# Display logo if available and not in dry run mode
if ! $DRY_RUN; then
  if [ -x "$(command -v tte)" ]; then
    tte -i ~/.local/share/omarchy/logo.txt --frame-rate 920 laseretch 2>/dev/null || true
    echo
    echo "You're done! So we're ready to reboot now..." | tte --frame-rate 640 wipe 2>/dev/null || true
  else
    echo "
        ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
        █  ▄▄▄  █▄ ▄█ ▄▄▄█ ▄▄▄█ ▄▄▀█▀▄▄▀█ ▄▀▄ █▀▄▀█ ▄▄▀█ ▄▄█ ▄▄▀
        █ █▄▀▀▄▄█ █ █▄▄▄█▄▄▄▀█ ▀▀▄█ ██ █ █ █ █ █▀█ █▀▄█▄▄▄█ ██ 
        █▄▄▄▄▄▄▄█▄▄▄█▄▄▄█▄▄▄▄█▄█▄▄█▄▄█▄█▄█ ▀▄█▄█▄█▄█▄▄█▄▄▄█▄██▄
        "
    echo "You're done! So we're ready to reboot now..."
  fi

  if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
    if $DRY_RUN; then
      echo "[DRY RUN] Would remove installer sudoers file"
    else
      sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
      echo -e "\nRemember to remove USB installer!\n\n"
    fi
  fi

  # Ask user if they want to reboot
  if ! $DRY_RUN; then
    read -p "Do you want to reboot now? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      echo "Rebooting in 5 seconds..."
      sleep 5
      reboot
    else
      echo "Skipping reboot. You can manually reboot later to apply all changes."
    fi
  fi
fi
