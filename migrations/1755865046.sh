echo "Switch from lazydocker-bin to lazydocker official"

if pacman -Q lazydocker-bin >/dev/null; then
  sudo pacman -Rns --noconfirm lazydocker-bin
  sudo pacman -S --noconfirm lazydocker
fi
