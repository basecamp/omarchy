# Replace the installer's offline pacman configuration with online repositories.
if [[ $(uname -m) == aarch64 ]]; then
  # Install the keyring before replacing the offline package source.
  omarchy-pkg-add archlinuxarm-keyring

  cp -f "$OMARCHY_PATH/default/pacman/pacman-aarch64.conf" /etc/pacman.conf
  cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-aarch64" /etc/pacman.d/mirrorlist

  # Trust every installed keyring before the first signed sync.
  pacman-key --init
  pacman-key --populate
else
  cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
  cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist
fi

# Wait for CUPS to own the file, the way omarchy-settings does, so pacman does
# not turn the override into a .pacnew during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
