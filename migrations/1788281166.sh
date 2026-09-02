echo "Install the AFK Monitor bar plugin alongside the AFK CLI"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-afk-plugin-install || true
fi
