# https://wiki.archlinux.org/title/Systemd-resolved
# The target does not need the stub file to exist yet; systemd-resolved creates
# it at boot.
echo "Symlinking resolved stub-resolv to /etc/resolv.conf"
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
