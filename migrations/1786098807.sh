echo "Relink agent skill symlinks to default/agents/skills/omarchy"

mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills
ln -sfn "$OMARCHY_PATH/default/agents/skills/omarchy" ~/.agents/skills/omarchy
ln -sfn "$OMARCHY_PATH/default/agents/skills/omarchy" ~/.claude/skills/omarchy
ln -sfn "$OMARCHY_PATH/default/agents/skills/omarchy" ~/.codex/skills/omarchy
ln -sfn "$OMARCHY_PATH/default/agents/skills/omarchy" ~/.pi/agent/skills/omarchy
