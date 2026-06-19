# DNF preflight: enable RPM Fusion and refresh repos before package install

echo -e "\e[32m\nConfiguring DNF and enabling required repositories\e[0m"

# Speed up DNF
if ! grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf; then
  echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
  echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
fi

# Enable RPM Fusion free + nonfree (needed for codecs, obs-studio, etc.)
if ! omarchy-pkg-present rpmfusion-free-release; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
fi

# Enable Flathub for Flatpak apps
if ! flatpak remote-list | grep -q flathub; then
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# Refresh all package metadata
sudo dnf upgrade -y --refresh
