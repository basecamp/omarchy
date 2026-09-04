echo "Fix Framework Laptop 13 AMD Ryzen AI 300 microphone input"

if omarchy-hw-framework13-ai300; then
  source "$OMARCHY_PATH/install/hardware/framework/fix-framework13-ai300-mic.sh"
  omarchy-state set reboot-required
fi
