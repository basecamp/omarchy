echo "Replace Gemini CLI with Antigravity CLI in default agent and mise wrappers"

rm -f "$HOME/.local/bin/gemini"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install ubi:google-antigravity/antigravity-cli agy
fi

agent_file="$HOME/.config/omarchy/defaults/agent"
if [[ -f $agent_file ]]; then
  read -r agent <"$agent_file"
  if [[ $agent == "gemini" || $agent == "gemini-cli" ]]; then
    printf 'antigravity\n' >"$agent_file"
  fi
fi
