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

# journald only reads its config at startup; write a drop-in and restart so the
# cap applies without waiting for a reboot.
as_root mkdir -p /etc/systemd/journald.conf.d
printf '%s\n' '[Journal]' 'SystemMaxUse=1G' |
  as_root tee /etc/systemd/journald.conf.d/10-journal-cap.conf >/dev/null
as_root systemctl try-restart systemd-journald >/dev/null 2>&1 || true

# Machine-wide, so a second user on the same box finds it already done.
as_root systemctl daemon-reload >/dev/null 2>&1 || true
as_root systemctl enable --now paccache.timer >/dev/null 2>&1
as_root systemctl enable --now btrfs-balance.timer >/dev/null 2>&1
