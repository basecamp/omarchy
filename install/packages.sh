# Function to check if a package is installed
is_installed() {
    pacman -Q "$1" &>/dev/null
}

# Function to check if a browser is already installed
is_browser_installed() {
    which chromium &>/dev/null || which google-chrome &>/dev/null || which brave &>/dev/null
}

# Create arrays for all packages and packages to install
all_packages=(
  "1password-beta"
  "1password-cli"
  "alacritty"
  "avahi"
  "bash-completion"
  "bat"
  "blueberry"
  "brightnessctl"
  "btop"
  "cargo"
  "clang"
  "cups"
  "cups-browsed"
  "cups-filters"
  "cups-pdf"
  "docker"
  "docker-buildx"
  "docker-compose"
  "dust"
  "evince"
  "eza"
  "fastfetch"
  "fcitx5"
  "fcitx5-gtk"
  "fcitx5-qt"
  "fd"
  "ffmpegthumbnailer"
  "fzf"
  "gcc14"
  "github-cli"
  "gnome-calculator"
  "gnome-keyring"
  "gnome-themes-extra"
  "gum"
  "gvfs-mtp"
  "hypridle"
  "hyprland"
  "hyprland-qtutils"
  "hyprlock"
  "hyprpicker"
  "hyprshot"
  "hyprsunset"
  "imagemagick"
  "impala"
  "imv"
  "inetutils"
  "jq"
  "kdenlive"
  "kvantum-qt5"
  "lazydocker"
  "lazygit"
  "less"
  "libqalculate"
  "libreoffice"
  "llvm"
  "localsend"
  "luarocks"
  "mako"
  "man"
  "mariadb-libs"
  "mise"
  "mpv"
  "nautilus"
  "noto-fonts"
  "noto-fonts-cjk"
  "noto-fonts-emoji"
  "noto-fonts-extra"
  "nss-mdns"
  "nvim"
  "obs-studio"
  "obsidian"
  "omarchy-chromium"
  "pamixer"
  "pinta"
  "playerctl"
  "plocate"
  "plymouth"
  "polkit-gnome"
  "postgresql-libs"
  "power-profiles-daemon"
  "python-gobject"
  "python-poetry-core"
  "python-terminaltexteffects"
  "ripgrep"
  "satty"
  "signal-desktop"
  "slurp"
  "spotify"
  "starship"
  "sushi"
  "swaybg"
  "swayosd"
  "system-config-printer"
  "tldr"
  "tree-sitter-cli"
  "ttf-cascadia-mono-nerd"
  "ttf-font-awesome"
  "ttf-ia-writer"
  "ttf-jetbrains-mono"
  "typora"
  "tzupdate"
  "ufw"
  "ufw-docker"
  "unzip"
  "uwsm"
  "walker-bin"
  "waybar"
  "wf-recorder"
  "whois"
  "wiremix"
  "wireplumber"
  "wl-clip-persist"
  "wl-clipboard"
  "wl-screenrec"
  "xdg-desktop-portal-gtk"
  "xdg-desktop-portal-hyprland"
  "xmlstarlet"
  "xournalpp"
  "yaru-icon-theme"
  "yay"
  "zoxide"
)

packages_to_install=()

# Check which packages need to be installed
echo "Checking installed packages..."
for package in "${all_packages[@]}"; do
    # Skip omarchy-chromium if a browser is already installed
    if [[ "$package" == "omarchy-chromium" ]] && is_browser_installed; then
        echo "Browser already installed, skipping $package..."
        continue
    fi
    
    if ! is_installed "$package"; then
        packages_to_install+=("$package")
    else
        echo "Package $package is already installed, skipping..."
    fi
done

# Install only the packages that aren't already installed
if [ ${#packages_to_install[@]} -gt 0 ]; then
    echo "Installing missing packages: ${packages_to_install[*]}"
    sudo pacman -S --noconfirm --needed "${packages_to_install[@]}"
else
    echo "All required packages are already installed."
fi
