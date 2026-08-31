echo "Install ori (OpenRouter's agent harness) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install github:OpenRouterLabs/ori-releases ori
fi
