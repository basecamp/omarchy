# Chroot installations have some differences
if ! cmp -s /proc/1/root/ / 2>/dev/null; then
  export OMARCHY_CHROOT_INSTALL=1
fi

chrootable_systemctl_enable() {
  if [ -n "${OMARCHY_CHROOT_INSTALL:-}" ]; then
    sudo systemctl enable $1
  else
    sudo systemctl enable --now $1
  fi
}
