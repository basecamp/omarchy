# Enable services only. Installs are followed by reboot, so don't start/reload
# daemons mid-install. UFW and hardware-gated services stay in their own scripts.
systemctl enable cups.service
systemctl enable avahi-daemon.service
systemctl enable linux-modules-cleanup.service
systemctl enable docker.socket
systemctl enable systemd-resolved.service
systemctl enable NetworkManager.service
# Don't let network-online.target hold up graphical.target waiting for
# DHCP/Wi-Fi association. Nothing in the session needs to block on the network.
# Mirrors the systemd-networkd-wait-online mask in install/hardware/network.sh.
systemctl mask NetworkManager-wait-online.service
systemctl enable power-profiles-daemon.service
systemctl enable sddm.service
# Kill one runaway app scope instead of letting reclaim thrashing take the
# whole session down. [Install] pulls in systemd-oomd.socket via Also=, which
# is what the user manager reports app.slice candidacy over.
systemctl enable systemd-oomd.service
# Cap the journal at 1G so log growth can't eat the raw disk space btrfs needs
# for new metadata chunks. journald only reads its config at startup, and
# installs are followed by reboot, so the drop-in cap lands on first boot.
mkdir -p /etc/systemd/journald.conf.d
printf '%s\n' '[Journal]' 'SystemMaxUse=1G' > /etc/systemd/journald.conf.d/10-journal-cap.conf
# Trim the pacman cache so it can't grow into that same space either.
systemctl enable paccache.timer
# Reclaim low-usage btrfs chunks weekly to reduce allocation pressure.
systemctl enable btrfs-balance.timer
