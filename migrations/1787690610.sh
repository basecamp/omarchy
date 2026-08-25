echo "Set the timezone through systemd-timedated instead of a passwordless sudo rule"

# The timezone menu now calls org.freedesktop.timedate1.SetTimezone over the
# bus, so /etc/sudoers.d/omarchy-tzupdate and its NOPASSWD grant on
# /usr/bin/timedatectl are gone from the package. pacman drops files it owns
# when a new version stops shipping them, but an install that picked the file up
# unowned -- the 3.x to 4.0 upgrade passed --overwrite for this path -- keeps it,
# and with it a passwordless grant nothing uses any more. Remove it explicitly.
if [[ -e /etc/sudoers.d/omarchy-tzupdate ]]; then
  sudo rm -f /etc/sudoers.d/omarchy-tzupdate
fi
