echo "Remove old PulseAudio volume control GUI"

if omarchy-pkg-present pavucontrol; then
  omarchy-pkg-drop pavucontrol
  omarchy-refresh-applications
fi
