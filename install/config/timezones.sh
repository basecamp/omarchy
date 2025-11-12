# Ensure /etc/localtime exists (set to UTC as fallback if missing)
# Necessary for any system that doesn't have a timezone set, or where the
# clock is set to a time that is in the past. Without the proper timezone
# set, ssl handshake errors can occur when accessing HTTPS resources.
if [ ! -e /etc/localtime ]; then
  echo "No timezone set, defaulting to UTC..."
  sudo ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi

# Ensure timezone can be updated without needing to sudo
sudo tee /etc/sudoers.d/omarchy-tzupdate >/dev/null <<EOF
%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl
EOF
sudo chmod 0440 /etc/sudoers.d/omarchy-tzupdate
