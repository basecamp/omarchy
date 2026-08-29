# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist

# omarchy-settings skips these overrides until CUPS is actually present to
# avoid pacman creating .pacnew files during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf && -f /etc/cups/cups-files.conf ]]; then
  systemd-sysusers /etc/sysusers.d/omarchy-cups-browsed.conf
  cp -f "$OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf" /etc/cups/cups-browsed.conf
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-browsed.conf.pacnew /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
