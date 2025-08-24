echo "Install satty for the new screenshot flow"

if ! command -v satty &>/dev/null; then
  sudo pacman -S --noconfirm --needed satty
fi
