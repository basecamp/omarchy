echo "Add potentially missing dependency for power profile controls"

if ! yay -Q python-gobject &>/dev/null; then
  yay -S --noconfirm python-gobject
fi
