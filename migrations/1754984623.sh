echo "Ensure DNS resolver configuration is properly symlinked"

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
