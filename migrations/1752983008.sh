if ! command -v zoom &>/dev/null; then
  echo "Add missing installation of Zoom"
  yay -S --noconfirm --needed zoom
fi
