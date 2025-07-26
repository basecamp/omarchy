echo "Add wtype to enable key presses simulation"
if ! command -v wtype &>/dev/null; then
  yay -S --noconfirm --needed wtype
fi
