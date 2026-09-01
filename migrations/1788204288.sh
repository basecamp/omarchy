echo "Install dim and kimi via mise wrappers"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:dimcode dim
  omarchy-mise-install npm:@moonshot-ai/kimi-code kimi
fi
