# Place in ~/.claude/skills since all tools populate from there as well as their own sources
mkdir -p ~/.claude/skills
ln -s $OMARCHY_PATH/default/omarchy-skill ~/.claude/skills/omarchy
