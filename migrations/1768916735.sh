echo "Fix microphone gain and audio mixing on Asus ROG laptops"

source "$OMARCHY_PATH/install/config/hardware/asus/fix-mic.sh"
source "$OMARCHY_PATH/install/config/hardware/asus/fix-audio-mixer.sh"

if omarchy-hw-asus-rog; then
  omarchy-restart-pipewire
fi
