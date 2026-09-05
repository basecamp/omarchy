# Shared apple-gmux backlight helpers. Sourced; no shebang, no work on source.

gmux_udev_src() {
  printf '%s\n' "${OMARCHY_GMUX_UDEV_SRC:-$OMARCHY_PATH/default/udev/apple-gmux-backlight.rules}"
}

gmux_udev_dest() {
  printf '%s\n' "${OMARCHY_GMUX_UDEV_DEST:-/etc/udev/rules.d/90-apple-gmux-backlight.rules}"
}

gmux_install_rule() {
  local src dest
  src=$(gmux_udev_src)
  dest=$(gmux_udev_dest)
  mkdir -p "$(dirname "$dest")"
  /usr/bin/install -Dm644 "$src" "$dest"
}

# Attach systemd-backlight and snapshot the current level so the next boot
# has something to restore. Tests retarget dest away from /etc and skip this.
gmux_activate() {
  local dest
  dest=$(gmux_udev_dest)
  [[ $dest == /etc/udev/rules.d/* ]] || return 0

  /usr/bin/udevadm control --reload
  /usr/bin/udevadm trigger --action=add --subsystem-match=backlight --sysname-match=gmux_backlight
  systemctl start systemd-backlight@backlight:gmux_backlight.service
  /usr/lib/systemd/systemd-backlight save backlight:gmux_backlight
}
