echo "Enable Dell XPS 13 sidecar speaker amplifiers"

if omarchy-hw-dell-xps13-sidecar-amps; then
  source "$OMARCHY_PATH/install/hardware/dell-xps13-sidecar-amps.sh"
  omarchy-state set reboot-required
fi
