echo "Adding gnome-keyring to make 1password work with 2FA codes"

if ! command -v gnome-keyring &>/dev/null; then
  yay -S --noconfirm --needed gnome-keyring
fi
