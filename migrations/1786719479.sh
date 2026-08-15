echo "Replace the Gemini coding agent with Antigravity"

agent_file="$HOME/.config/omarchy/defaults/agent"

selected_gemini=false
if [[ -f $agent_file ]] && grep -qxF gemini "$agent_file"; then
  selected_gemini=true
fi

# Choosing Gemini was opting into an agent, so its replacement follows even for
# someone who removed the preinstalls. Otherwise the default rewritten below
# would name a command that is not there.
if omarchy-cmd-missing agy &&
  { [[ $selected_gemini == "true" ]] || [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; }; then
  omarchy-mise-install antigravity-cli agy
fi

if [[ $selected_gemini == "true" ]]; then
  printf '%s\n' agy >"$agent_file"
fi

# Remove Preinstalls no longer lists gemini, so Omarchy's own wrapper would
# linger with nothing left to clean it up. A hand-written one is left alone.
if [[ -f $HOME/.local/bin/gemini ]] && grep -Fq 'mise use -g "gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi
