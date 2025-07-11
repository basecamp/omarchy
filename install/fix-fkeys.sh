if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
  echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf

  # Rely on install/plymouth.sh to do the rebuild
  # sudo mkinitcpio -P
fi
