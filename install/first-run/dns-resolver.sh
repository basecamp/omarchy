# https://wiki.archlinux.org/title/Systemd-resolved
echo "Enable and start systemd-resolved, then symlink stub-resolv to /etc/resolv.conf"

sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
