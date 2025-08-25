echo "Remove needless fcitx5-configtool package"
if pacman -Qe fcitx5-configtool &>/dev/null; then
  sudo pacman -Rns --noconfirm fcitx5-configtool
fi
