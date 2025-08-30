echo "Add back ttf-ia-writer if it was missing"

if ! pacman -Q ttf-ia-writer 2>/dev/null; then
  sudo pacman -S --noconfirm ttf-ia-writer
fi
