echo "Ensure TTE and dependencies are installed"

if ! pacman -Q python-poetry-core &>/dev/null; then
  sudo pacman -S --noconfirm python-poetry-core
fi

if ! pacman -Q python-terminaltexteffects &>/dev/null; then
  sudo pacman -S --noconfirm python-terminaltexteffects
fi
