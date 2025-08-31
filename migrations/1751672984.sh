echo "Add LocalSend as new default application"

if ! command -v localsend &>/dev/null; then
  sudo pacman -S --noconfirm --needed localsend
fi
