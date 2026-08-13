echo "Replace the deprecated Gemini CLI with Antigravity (agy)"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install github:google-antigravity/antigravity-cli agy
fi

if [[ -f $HOME/.local/bin/gemini ]] && grep -Fq 'mise use -g "gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi

agent_file="$HOME/.config/omarchy/defaults/agent"
if [[ -f $agent_file ]] && [[ $(<$agent_file) == "gemini" ]]; then
  printf 'agy\n' >"$agent_file"
fi
