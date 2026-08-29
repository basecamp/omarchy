# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist

# Each override waits for the package that owns the file it replaces, the way
# omarchy-settings does, so pacman does not turn it into a .pacnew during ISO
# package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

# cups-browsed is no longer part of the default install, so this waits for a
# machine that adds discovery back by hand. Writing the override before then
# would leave a configuration file for a package nothing installed, and pacman
# would later land the package's own copy beside it as a .pacnew.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf && -f /etc/cups/cups-browsed.conf ]]; then
  systemd-sysusers /etc/sysusers.d/omarchy-cups-browsed.conf
  cp -f "$OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf" /etc/cups/cups-browsed.conf
  rm -f /etc/cups/cups-browsed.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
