echo "Add LocalSend as new default application"

if ! command -v localsend &>/dev/null; then
  yay -S --noconfirm --needed localsend-bin
fi
