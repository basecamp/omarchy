# Central place for unconditional service enables. Services that should NOT
# be started during install (sddm, ufw) live in their own scripts. Hardware-
# gated services (t2fanrd, intel_lpmd, thermald, omarchy-nvme-suspend-fix)
# also live with their detection.
#
# Two variants:
#   chrootable_systemctl_enable      -> enable + start now (safe to start)
#   chrootable_systemctl_enable_only -> enable only (don't risk starting during
#                                       install)
chrootable_systemctl_enable      bluetooth.service
chrootable_systemctl_enable      cups.service
chrootable_systemctl_enable      cups-browsed.service
chrootable_systemctl_enable      avahi-daemon.service
chrootable_systemctl_enable      linux-modules-cleanup.service
chrootable_systemctl_enable_only docker.socket
chrootable_systemctl_enable_only iwd.service
chrootable_systemctl_enable_only power-profiles-daemon.service
