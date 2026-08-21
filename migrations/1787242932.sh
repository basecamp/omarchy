echo "Install Antigravity (agy) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install aqua:google-antigravity/antigravity-cli agy
fi
