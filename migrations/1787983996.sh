echo "Apply Steam Input permissions to uinput"

[[ -e /dev/uinput ]] || exit 0
sudo systemd-tmpfiles --create /etc/tmpfiles.d/omarchy-uinput.conf
