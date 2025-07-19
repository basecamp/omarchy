echo "Remove needless fcitx5-configtool package"
if command -v fcitx5-configtool &>/dev/null; then
  yay -Rns --noconfirm fcitx5-configtool
fi
