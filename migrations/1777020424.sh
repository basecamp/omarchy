echo "Enable acer_wmi predator_v4 on Acer Predator/Nitro laptops"

if omarchy-hw-acer-predator; then
  MODPROBE_CONF=/etc/modprobe.d/acer-wmi.conf
  if ! grep -qs "predator_v4=1" "$MODPROBE_CONF" 2>/dev/null; then
    echo "options acer_wmi predator_v4=1" | sudo tee "$MODPROBE_CONF" >/dev/null
    echo "Reboot required for acer_wmi predator_v4 to take effect."
  fi
fi
