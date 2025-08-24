echo "Add Terminal Text Effects for rizzing Omarchy"
if omarchy-pkg-aur-accessible; then
  if ! yay -Q python-terminaltexteffects &>/dev/null; then
    yay -S --noconfirm --needed python-terminaltexteffects
  fi
else
  echo -e "\n\e[31mAUR is unavailable. Install python-terminaltexteffects via AUR manually later.\e[0m"
fi
