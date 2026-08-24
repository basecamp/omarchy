echo "Install junie (JetBrains' coding agent) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:@jetbrains/junie junie
fi
