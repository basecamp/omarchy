echo "Install Amp coding agent mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:@ampcode/cli amp
fi
