echo "Switch from lazydocker-bin to lazydocker official"

if yay -Q lazydocker-bin >/dev/null; then
  yay -Rns --noconfirm lazydocker-bin
  yay -S --noconfirm lazydocker
fi
