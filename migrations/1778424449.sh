echo "Set your city for the live weather widget (so it works behind VPNs and on travel)"

if [[ -s "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/weather-location" ]]; then
  exit 0
fi

if [[ ! -t 0 ]] || ! command -v gum >/dev/null 2>&1; then
  echo "Skipping prompt (non-interactive). Set later via Setup → Weather."
  exit 0
fi

omarchy-weather-set-location
