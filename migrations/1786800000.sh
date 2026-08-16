echo "Replace Gemini CLI with Antigravity CLI in default agent and mise wrappers"

gemini_wrapper="$HOME/.local/bin/gemini"
if [[ -f $gemini_wrapper ]] && grep -q "mise" "$gemini_wrapper" 2>/dev/null; then
  rm -f "$gemini_wrapper"
fi

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install ubi:google-antigravity/antigravity-cli agy
fi

agent_file="$HOME/.config/omarchy/defaults/agent"
if [[ -f $agent_file ]]; then
  agent=$(<"$agent_file")
  if [[ $agent == "gemini" || $agent == "gemini-cli" ]]; then
    printf 'antigravity\n' >"$agent_file"
  fi
fi
