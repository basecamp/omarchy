# Install iwd explicitly if it wasn't included in archinstall
# This can happen if archinstall used ethernet
if ! command -v iwd &>/dev/null; then
  yay -S --noconfirm --needed iwd
  sudo systemctl enable --now iwd.service
fi
