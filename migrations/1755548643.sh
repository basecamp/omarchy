echo "Install wf-recorder for intel based device"

if lspci | grep -Eqi 'nvidia|intel.*graphics'; then
  sudo pacman -S --noconfirm --needed wf-recorder
fi
