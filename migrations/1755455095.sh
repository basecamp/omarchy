echo "Ensure TTE and dependencies are installed"

if ! yay -Q python-poetry-core &>/dev/null; then
  yay -S --noconfirm python-poetry-core
fi

if ! yay -Q python-terminaltexteffects &>/dev/null; then
  yay -S --noconfirm python-terminaltexteffects
fi
