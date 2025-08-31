echo "Add missing installation of bat (used by the ff alias)"
if ! command -v bat &>/dev/null; then
  # Add missing installation of bat
  sudo pacman -S --noconfirm --needed bat
fi
