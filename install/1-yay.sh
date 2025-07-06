# Install build tools for Fedora
sudo dnf groupinstall -y "Development Tools" "Development Libraries"
sudo dnf install -y rpm-build rpmdevtools

# Note: yay is Arch-specific AUR helper, not available on Fedora
# Most packages that were available through AUR may need to be installed
# via Flatpak, AppImage, or compiled from source on Fedora

# if ! command -v yay &>/dev/null; then
#   git clone https://aur.archlinux.org/yay-bin.git
#   cd yay-bin
#   makepkg -si --noconfirm
#   cd ~
#   rm -rf yay-bin
# fi
