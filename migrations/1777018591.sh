echo "Copy helium-flags.conf to ~/.config/ if missing"

if [[ ! -f ~/.config/helium-flags.conf ]]; then
  omarchy-refresh-config helium-flags.conf
fi

echo "Create /etc/helium/policies/managed for theme policy injection"
sudo mkdir -p /etc/helium/policies/managed
sudo chmod 777 /etc/helium/policies/managed
