echo "Installing missing fd terminal tool for finding files"

if ! command -v fd &>/dev/null; then
  yay -S --noconfirm --needed fd
fi
