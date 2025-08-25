echo "Add Terminal Text Effects for rizzing Omarchy"

if ! pacman -Q python-terminaltexteffects &>/dev/null; then
  sudo pacman -S --noconfirm python-terminaltexteffects
fi
