echo "Install MiniMax's official CLI via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:mmx-cli mmx
fi
