echo "Fix microphone gain and audio mixing on Asus ROG laptops"

source "$OMARCHY_PATH/install/config/hardware/fix-asus-rog-mic.sh"
source "$OMARCHY_PATH/install/config/hardware/fix-asus-rog-audio-mixer.sh"

if [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == "ASUSTeK COMPUTER INC." ]] &&
   grep -q "ROG" /sys/class/dmi/id/product_family 2>/dev/null; then
  omarchy-restart-pipewire
fi
