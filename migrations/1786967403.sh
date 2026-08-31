echo "Install Kimi coding agent mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:@moonshot-ai/kimi-code kimi
fi
