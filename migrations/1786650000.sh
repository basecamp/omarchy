echo "Install Antigravity default coding agent mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install antigravity-cli agy
  omarchy-mise-install antigravity-cli antigravity agy
fi

if [[ -f $HOME/.local/bin/gemini ]] && grep -Fq 'mise use -g "gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi

agent_file="$HOME/.config/omarchy/defaults/agent"
if [[ -f $agent_file ]] && [[ $(cat "$agent_file") == "gemini" ]]; then
  printf 'antigravity\n' >"$agent_file"
fi
