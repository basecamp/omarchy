echo "Install AFK (browser-first coding agent) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install 'forgejo:mooglest/public[api_url=https://git.mooglest.com/api/v1]' afk
fi
