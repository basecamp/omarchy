echo "Replace the Gemini coding agent with Antigravity"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

agent_file="$HOME/.config/omarchy/defaults/agent"
skills_source="$OMARCHY_PATH/default/agents/skills"

# Read the default the way omarchy-default-agent reads it, so this migration and
# the launcher always agree on which agent is selected.
selected_agent=""
if [[ -f $agent_file ]]; then
  read -r selected_agent <"$agent_file" || true
fi

# Choosing Gemini was opting into an agent, so its replacement follows even for
# someone who removed the preinstalls. Otherwise the default rewritten below
# would name a command that is not there.
if omarchy-cmd-missing agy &&
  { [[ $selected_agent == "gemini" ]] || [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; }; then
  omarchy-mise-install antigravity-cli agy
fi

if [[ $selected_agent == "gemini" ]]; then
  printf '%s\n' agy >"$agent_file"
fi

# Remove Preinstalls no longer lists gemini, so Omarchy's own wrapper would
# linger with nothing left to clean it up. Anchored to the line the installer
# writes, so a hand-written wrapper that merely mentions it is left alone.
if [[ -f $HOME/.local/bin/gemini ]] && grep -Eq '^mise use -g .*"gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi

if [[ -d $skills_source ]]; then
  mkdir -p "$HOME/.gemini/config/skills"
  for skill in "$skills_source"/*/; do
    [[ -d $skill ]] || continue
    name=${skill%/}
    ln -sfn "$name" "$HOME/.gemini/config/skills/${name##*/}"
  done
fi
