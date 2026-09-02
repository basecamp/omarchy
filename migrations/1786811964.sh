echo "Add the omarchy-plugin-dev agent skill"

# omarchy-provision-user already loops every skill directory for new installs;
# existing installs need this new one linked in by hand. Codex and Pi both
# discover ~/.agents/skills, so only ~/.agents/skills and ~/.claude/skills
# need their own copy of the link.
skill="$OMARCHY_PATH/default/agents/skills/omarchy-plugin-dev"

if [[ -d $skill ]]; then
  mkdir -p ~/.agents/skills ~/.claude/skills
  ln -sfn "$skill" ~/.agents/skills/omarchy-plugin-dev
  ln -sfn "$skill" ~/.claude/skills/omarchy-plugin-dev
fi
