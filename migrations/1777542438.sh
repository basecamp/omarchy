echo "Replace coterie of individual Elephant packages with the single elephant-all package"

if omarchy-pkg-present omarchy-walker; then
  yes | sudo pacman -S --needed elephant-all walker
  sudo pacman -R --noconfirm omarchy-walker
fi
