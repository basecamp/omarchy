echo "Install Cursor Agent mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install asdf:icholy/asdf-cursor-agent cursor-agent
fi
