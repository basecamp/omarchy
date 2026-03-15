echo "Fix microphone gain and audio mixing on Asus ROG laptops"

source "$OMARCHY_PATH/install/config/hardware/fix-asus-rog-mic.sh"
source "$OMARCHY_PATH/install/config/hardware/fix-asus-rog-audio-mixer.sh"

if omarchy-hw-asus-rog; then
  omarchy-restart-pipewire
fi
