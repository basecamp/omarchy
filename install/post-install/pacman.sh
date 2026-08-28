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

# omarchy-settings skips this override until cups-browsed is actually present
# to avoid pacman creating cups-browsed.conf.pacnew during ISO package install.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf && -d /etc/cups ]]; then
  cp -f "$OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf" /etc/cups/cups-browsed.conf
  rm -f /etc/cups/cups-browsed.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
