echo "Copy helium-flags.conf to ~/.config/ if missing"

if [[ ! -f ~/.config/helium-flags.conf ]]; then
  omarchy-refresh-config helium-flags.conf
fi
