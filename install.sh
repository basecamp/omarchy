# Omarchy Installation Script for Fedora Linux
# Adapted from the original Arch Linux version

# Exit immediately if a command exits with a non-zero status
set -e

# Fedora-specific prerequisites
echo "Ensuring Fedora prerequisites are met..."

# Enable RPM Fusion repositories (needed for multimedia and proprietary packages)
if ! rpm -q rpmfusion-free-release &>/dev/null; then
  echo "Enabling RPM Fusion repositories..."
  sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# Update system packages
echo "Updating system packages..."
sudo dnf update -y

# Give people a chance to retry running the installation
trap 'echo "Omarchy installation failed! You can retry by running: source ~/.local/share/omarchy/install.sh"' ERR

# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do source "$f"; done

# Ensure locate is up to date now that everything has been installed
sudo updatedb

gum confirm "Reboot to apply all settings?" && reboot
