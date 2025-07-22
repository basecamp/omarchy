echo "Install missing docker-buildx package for out-of-the-box Kamal compatibility"

if ! docker buildx version &>/dev/null; then
  yay -S --noconfirm --needed docker-buildx
fi
