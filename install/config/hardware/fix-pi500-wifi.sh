# Enable Wi-Fi and Bluetooth on Raspberry Pi 500
# The default Arch Linux ARM image has dtoverlay=disable-wifi and dtoverlay=disable-bt
# in /boot/config.txt which prevents the wireless hardware from being detected

if [[ ! -f /sys/firmware/devicetree/base/model ]]; then
  exit 0
fi

model=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

if [[ "$model" == *"Raspberry Pi 500"* ]] || [[ "$model" == *"Raspberry Pi 5"* ]]; then
  echo "Raspberry Pi 5/500 detected: enabling Wi-Fi and Bluetooth in boot config"

  if [[ -f /boot/config.txt ]]; then
    # Comment out disable-wifi if it's enabled
    if grep -q "^dtoverlay=disable-wifi" /boot/config.txt; then
      sudo sed -i 's/^dtoverlay=disable-wifi/#dtoverlay=disable-wifi/' /boot/config.txt
      echo "  - Enabled Wi-Fi (commented out disable-wifi overlay)"
    fi

    # Comment out disable-bt if it's enabled
    if grep -q "^dtoverlay=disable-bt" /boot/config.txt; then
      sudo sed -i 's/^dtoverlay=disable-bt/#dtoverlay=disable-bt/' /boot/config.txt
      echo "  - Enabled Bluetooth (commented out disable-bt overlay)"
    fi
  fi
fi
