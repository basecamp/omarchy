omarchy_desktop_packages=(
  brightnessctl
  playerctl
  pamixer
  pavucontrol
  wireplumber
  fcitx5
  fcitx5-gtk
  fcitx5-qt
  fcitx5-configtool
  wl-clip-persist
  nautilus
  sushi
  ffmpegthumbnailer
  mpv
  evince
  imv
  chromium
)

# Initialize global array if it doesn't exist
if [ -z "${omarchy_failed_packages+x}" ]; then
  omarchy_failed_packages=()
fi

for pkg in "${omarchy_desktop_packages[@]}"; do
  echo "Installing $pkg..."
  if ! yay -S --noconfirm --needed "$pkg"; then
    gum style --foreground 196 --bold "✗ Failed to install $pkg"
    omarchy_failed_packages+=("$pkg")
  fi
done

unset omarchy_desktop_packages