# Place in ~/.claude/skills since all tools populate from there as well as their own sources
mkdir -p ~/.claude/skills
ln -sfn $OMARCHY_PATH/default/omarchy-skill ~/.claude/skills/omarchy

# Also place in ~/.codex/skills for OpenAI Codex CLI
mkdir -p ~/.codex/skills
ln -sfn $OMARCHY_PATH/default/omarchy-skill ~/.codex/skills/omarchy
