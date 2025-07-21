echo "Add missing Dropbox dependencies"

# Dropbox is still there, but the dependencies aren't yet
if command -v dropbox-cli &>/dev/null && ! pacman -Q libappindicator-gtk3 &>/dev/null; then
  yay -S --noconfirm --needed dropbox libappindicator-gtk3 python-gpgme nautilus-dropbox
fi
