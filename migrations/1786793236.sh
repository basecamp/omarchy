echo "Add the AUR review skill and unify the plugin security preference"

skill="$OMARCHY_PATH/default/agents/skills/verify-aur-package"
if [[ -d $skill ]]; then
  for skills_dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
    mkdir -p "$skills_dir"
    link="$skills_dir/verify-aur-package"
    if [[ -L $link ]]; then
      continue
    elif [[ -e $link ]]; then
      continue
    fi
    ln -sfn "$skill" "$link" || echo "Could not link $link"
  done
fi

# PR #6771 stored a plugin-only answer. Carry an affirmative answer into the
# broader toggle when an agent is still selected, then retire the old setting.
preference="$HOME/.local/state/omarchy/settings/plugin-verification"
if [[ -f $preference ]]; then
  read -r remembered <"$preference" || true
  if [[ $remembered == "always" && -n $(omarchy-default-agent) ]]; then
    omarchy-toggle agent-security-scan on
  fi
  rm -f "$preference"
fi
