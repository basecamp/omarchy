echo "Install wf-recorder for intel based device"

if lspci | grep -Eqi 'nvidia|intel.*graphics'; then
  yay -S --noconfirm --needed wf-recorder
fi
