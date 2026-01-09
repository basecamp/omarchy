#!/bin/bash
# Setup OpenCode AI integration for Omarchy

set -eEo pipefail

echo "Setting up OpenCode AI integration..."

OMARCHY_AI="$OMARCHY_PATH/default/omarchy-ai"

# OpenCode workspace at ~/.config/ (where omarchian operates)

# AGENTS.md - project context for the workspace
cp -f "$OMARCHY_AI/AGENTS.md" ~/.config/AGENTS.md

# Local .opencode directory structure
mkdir -p ~/.config/.opencode/agents
mkdir -p ~/.config/.opencode/skills

# Copy agent
cp -f "$OMARCHY_AI/agents/omarchian.md" ~/.config/.opencode/agents/

# Copy skills
for skill_dir in "$OMARCHY_AI/skills"/*; do
  if [ -d "$skill_dir" ]; then
    skill_name=$(basename "$skill_dir")
    mkdir -p ~/.config/.opencode/skills/"$skill_name"
    cp -f "$skill_dir"/SKILL.md ~/.config/.opencode/skills/"$skill_name"/
  fi
done

echo "OpenCode AI configured:"
echo "  - Workspace: ~/.config/"
echo "  - Agent: ~/.config/.opencode/agents/omarchian.md"
echo "  - Skills: ~/.config/.opencode/skills/omarchy*"
echo ""
echo "Launch with: omarchy-ai"
