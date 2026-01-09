echo "Switch from hyprsunset to sunsetr for blue light filtering"

# Install sunsetr from AUR
if ! command -v sunsetr &>/dev/null; then
  yay -S --noconfirm --needed sunsetr
fi

# Stop hyprsunset if running
pkill -x hyprsunset 2>/dev/null || true

# Remove hyprsunset package (if installed)
if pacman -Qi hyprsunset &>/dev/null; then
  sudo pacman -Rns --noconfirm hyprsunset 2>/dev/null || true
fi

# Remove old config
rm -f ~/.config/hypr/hyprsunset.conf

# Install new sunsetr config
omarchy-refresh-sunsetr
