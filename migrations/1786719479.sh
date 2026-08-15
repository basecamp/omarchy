echo "Replace the Gemini coding agent with Antigravity"

agent_file="$HOME/.config/omarchy/defaults/agent"

if [[ ! -f "$HOME/.local/state/omarchy/preinstalls-removed" ]] && omarchy-cmd-missing agy; then
  omarchy-mise-install antigravity-cli agy
fi

if [[ -f $agent_file ]] && grep -qxF gemini "$agent_file"; then
  printf '%s\n' agy >"$agent_file"
fi

# Remove Preinstalls no longer lists gemini, so Omarchy's own wrapper would
# linger with nothing left to clean it up. A hand-written one is left alone.
if [[ -f $HOME/.local/bin/gemini ]] && grep -Fq 'mise use -g "gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi
