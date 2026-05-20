# _only variant skips --now to avoid starting iwd/docker/power-profiles-daemon
# during install (existing iwd would be interrupted; the others should defer
# to first boot). sddm, ufw, and hardware-gated services stay in their own
# scripts.
chrootable_systemctl_enable      bluetooth.service
chrootable_systemctl_enable      cups.service
chrootable_systemctl_enable      cups-browsed.service
chrootable_systemctl_enable      avahi-daemon.service
chrootable_systemctl_enable      linux-modules-cleanup.service
chrootable_systemctl_enable_only docker.socket
chrootable_systemctl_enable_only iwd.service
chrootable_systemctl_enable_only power-profiles-daemon.service
