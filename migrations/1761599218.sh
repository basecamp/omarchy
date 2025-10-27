echo "Installing omarchy-keyring to ensure package signature verification"

if omarchy-pkg-missing omarchy-keyring || ! sudo pacman-key --list-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 &>/dev/null; then
  sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
  omarchy-pkg-add omarchy-keyring
  sudo pacman-key --list-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571
fi
