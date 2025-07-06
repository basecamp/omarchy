sudo dnf install -y \
  brightnessctl playerctl pamixer pavucontrol wireplumber \
  fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool \
  nautilus sushi ffmpegthumbnailer gnome-calculator \
  chromium mpv \
  evince imv

# Note: These packages are not available in Fedora repos and need alternative installation:
# - wl-clip-persist: may need to be compiled from source
# - clipse-bin: AUR package, not available for Fedora
# - 1password-beta, 1password-cli: install from 1Password website
# - localsend-bin: install from GitHub releases or Flatpak
