# Printer config files now ship via omarchy-settings:
# - etc/systemd/resolved.conf.d/10-disable-multicast.conf (package-owned drop-in)
# - etc/nsswitch.conf (etc-overrides, replaces the previous in-place sed)
# - etc/cups/cups-browsed.conf (etc-overrides, replaces the previous append)
#
# This script only handles service enables, which the configurator path needs.
chrootable_systemctl_enable cups.service
chrootable_systemctl_enable avahi-daemon.service
chrootable_systemctl_enable cups-browsed.service
