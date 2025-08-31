echo "Add potentially missing dependency for power profile controls"

if ! pacman -Q python-gobject &>/dev/null; then
  sudo pacman -S --noconfirm python-gobject
fi
