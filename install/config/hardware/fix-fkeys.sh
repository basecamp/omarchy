# Ensure that F-keys on Apple-like keyboards (such as Lofree Flow84) are always F-keys
if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
  echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf
fi
