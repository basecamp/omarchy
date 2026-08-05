echo "Cap the journal size and enable cache trimming and weekly btrfs balancing"

# Fresh installs get these from install/config/enable-services.sh and the base
# package list. Existing installs need the same maintenance defaults, otherwise
# the journal and pacman cache keep growing and low-usage btrfs chunks are never
# reclaimed until the filesystem exhausts its metadata allocation.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# The btrfs-balance.timer ships with btrfsmaintenance, which is AUR-only.
if omarchy-pkg-missing btrfsmaintenance; then
  omarchy-pkg-aur-add btrfsmaintenance ||
    echo "Could not install btrfsmaintenance; low-usage btrfs chunks will not be reclaimed."
fi

# journald only reads its config at startup; reapply idempotently and restart
# so the cap applies without waiting for a reboot.
as_root sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=1G/' /etc/systemd/journald.conf ||
  echo "Could not cap the journal size at 1G."
as_root systemctl try-restart systemd-journald >/dev/null 2>&1 || true

# Machine-wide, so a second user on the same box finds it already done.
as_root systemctl daemon-reload >/dev/null 2>&1 || true
as_root systemctl enable paccache.timer >/dev/null 2>&1 ||
  echo "Could not enable paccache.timer; the pacman cache can grow without limit."
as_root systemctl enable btrfs-balance.timer >/dev/null 2>&1 ||
  echo "Could not enable btrfs-balance.timer."
