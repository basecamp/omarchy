# Central place for unconditional, safe-to-start-now service enables.
# Services that should NOT be started during install (sddm, ufw) live in
# their own scripts. Hardware-gated services (t2fanrd, intel_lpmd,
# thermald, omarchy-nvme-suspend-fix) also live with their detection.
chrootable_systemctl_enable bluetooth.service
chrootable_systemctl_enable cups.service
chrootable_systemctl_enable cups-browsed.service
chrootable_systemctl_enable avahi-daemon.service
chrootable_systemctl_enable docker.socket
chrootable_systemctl_enable iwd.service
chrootable_systemctl_enable linux-modules-cleanup.service
chrootable_systemctl_enable power-profiles-daemon.service
