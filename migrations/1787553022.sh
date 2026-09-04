echo "Seed Helium browser flags and migrate legacy helium-flags.conf"

# Migrate legacy misnamed flags file to correct helium-browser name
if [[ -f ~/.config/helium-flags.conf && ! -f ~/.config/helium-browser-flags.conf ]]; then
  cp -f ~/.config/helium-flags.conf ~/.config/helium-browser-flags.conf
fi

# Seed correct flags file for existing installs if missing
if [[ ! -f ~/.config/helium-browser-flags.conf ]]; then
  mkdir -p ~/.config
  cp -f "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/config/chromium-flags.conf" ~/.config/helium-browser-flags.conf
fi
