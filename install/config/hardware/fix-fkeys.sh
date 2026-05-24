# Ensure that F-keys on Apple-like keyboards (such as Lofree Flow84) are always F-keys
if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
  mkdir -p /etc/modprobe.d
  echo "options hid_apple fnmode=2" > /etc/modprobe.d/hid_apple.conf
fi
