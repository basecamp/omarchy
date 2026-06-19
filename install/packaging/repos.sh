# Enable all third-party repositories required by Omarchy before packages are installed.
# Order matters: repos must be available before packages that depend on them.

echo -e "\e[32m\nEnabling required third-party repositories\e[0m"

# ── Hyprland ecosystem ────────────────────────────────────────────────────────
# Provides: hyprland, hyprlock, hypridle, hyprsunset, hyprpicker,
#           xdg-desktop-portal-hyprland
# Maintainer: lionheartp — actively maintained for Fedora 44
echo "Enabling lionheartp/hyprland (Copr)..."
sudo dnf copr enable -y lionheartp/hyprland

# ── Walker app launcher ───────────────────────────────────────────────────────
# Provides: walker (replaces omarchy-walker from Arch AUR)
echo "Enabling errornointernet/walker (Copr)..."
sudo dnf copr enable -y errornointernet/walker

# ── SwayOSD ───────────────────────────────────────────────────────────────────
# Provides: swayosd (on-screen display for volume/brightness/capslock)
echo "Enabling erikreider/SwayNotificationCenter (Copr)..."
sudo dnf copr enable -y erikreider/SwayNotificationCenter

# ── Satty ─────────────────────────────────────────────────────────────────────
# Provides: satty (screenshot annotation tool, used by omarchy capture screenshot)
echo "Enabling mineiro/satty (Copr)..."
sudo dnf copr enable -y mineiro/satty

# ── 1Password ─────────────────────────────────────────────────────────────────
# Official vendor RPM repo from 1Password
if [[ ! -f /etc/yum.repos.d/1password.repo ]]; then
  echo "Adding 1Password official repo..."
  sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
  sudo sh -c 'cat > /etc/yum.repos.d/1password.repo <<EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF'
fi

# ── Docker ────────────────────────────────────────────────────────────────────
# Official Docker CE repo for Fedora
if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
  echo "Adding Docker official repo..."
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
fi

echo -e "\e[32mAll repositories enabled\e[0m"
sudo dnf makecache
