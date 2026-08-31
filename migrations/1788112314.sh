echo "Point rc-channel installs at the rc package repository"

# pacman-rc.conf shipped with [omarchy] pointing at the edge repository, a
# leftover from when release candidates published there. Candidates now publish
# to the dedicated rc channel, so a machine on the rc mirror was taking its
# omarchy packages from edge. Repoint only a conf that still carries the
# shipped pairing: an administrator who chose another combination keeps it.
if grep -q "https://rc-mirror.omarchy.org/" /etc/pacman.d/mirrorlist &&
  grep -q "^Server = https://pkgs.omarchy.org/edge/" /etc/pacman.conf; then
  sudo sed -i "s|^Server = https://pkgs.omarchy.org/edge/|Server = https://pkgs.omarchy.org/rc/|" /etc/pacman.conf
  echo "Switched the [omarchy] repository to the rc channel to match this machine's rc mirror."
fi
