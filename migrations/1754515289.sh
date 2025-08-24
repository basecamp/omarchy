echo "Update and restart Walker to resolve stuck Omarchy menu"

if omarchy-pkg-aur-accessible; then
  yay -Sy --noconfirm walker-bin
else
  echo -e "\n\e[31mAUR is unavailable. Update walker-bin via AUR manually later.\e[0m"
fi

omarchy-restart-walker
