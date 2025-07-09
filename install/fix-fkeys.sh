if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; do
  echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf
  sudo mkinitcpio -P
fi
