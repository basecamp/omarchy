echo "Enable acer_wmi predator_v4 on Acer Predator/Nitro laptops"

source "$OMARCHY_PATH/install/config/hardware/acer/enable-turbo-key.sh"

if omarchy-hw-acer-predator; then
  echo "Reboot required for acer_wmi predator_v4 to take effect."
fi
