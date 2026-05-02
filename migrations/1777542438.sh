echo "Replace coterie of individual Elephant packages with the single elephant-all package"

if omarchy-pkg-present omarchy-walker; then
  sudo pacman -R --noconfirm omarchy-walker
  yes | sudo pacman -S --needed elephant-all
fi
