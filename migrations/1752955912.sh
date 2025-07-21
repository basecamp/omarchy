echo "Install satty for the new screenshot flow"

if ! command -v satty &>/dev/null; then
  yay -S --noconfirm --needed satty
fi
