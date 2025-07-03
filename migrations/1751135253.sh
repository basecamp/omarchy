if ! command -v bat &>/dev/null; then
  # Add missing installation of bat
  echo "Add missing installation of bat (used by the ff alias)"
  yay -S --noconfirm --needed bat
fi
