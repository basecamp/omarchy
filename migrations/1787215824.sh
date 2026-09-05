echo "Install hey (hey-cli) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install hey-cli hey
fi
