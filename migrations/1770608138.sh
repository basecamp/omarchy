echo "Install legionaura on Lenovo gaming machines"

if omarchy-hw-lenovo-gaming && omarchy-pkg-missing legionaura; then
  omarchy-pkg-add legionaura
fi
