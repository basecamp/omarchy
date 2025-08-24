echo "Ensure TTE and dependencies are installed"

if omarchy-pkg-aur-accessible; then
  if ! yay -Q python-poetry-core &>/dev/null; then
    yay -S --noconfirm python-poetry-core
  fi

  if ! yay -Q python-terminaltexteffects &>/dev/null; then
    yay -S --noconfirm python-terminaltexteffects
  fi
else
  echo -e "\n\e[31mAUR is unavailable. Skipping installation. Please try manually later.\e[0m"
fi
