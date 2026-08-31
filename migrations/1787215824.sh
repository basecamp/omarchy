echo "Install hey (hey-cli) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install github:basecamp/hey-cli hey
fi
