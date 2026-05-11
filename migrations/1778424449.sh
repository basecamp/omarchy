echo "Set your city for the live weather widget (so it works behind VPNs and on travel)"

if [[ ! -s "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/weather-location" ]]; then
  omarchy-weather-set-location || true
fi
