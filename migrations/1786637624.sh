echo "Make terminal AI tools follow the Omarchy palette"

current_theme="$HOME/.local/state/omarchy/current/theme"

# These activations happen once. Codex and Grok then inherit every palette
# change from the terminal, while Claude and Pi continue receiving generated
# Omarchy theme files from the normal theme-switch hooks.
if [[ -d $HOME/.codex ]]; then
  omarchy-theme-set-codex --activate
fi

if [[ -d $HOME/.grok ]]; then
  omarchy-theme-set-grok --activate
fi

if [[ -d $HOME/.claude && -f $current_theme/claude.json ]]; then
  omarchy-theme-set-claude --activate
fi

if [[ -d $HOME/.pi/agent && -f $current_theme/pi.json ]]; then
  rm -f "$HOME/.pi/agent/extensions/omarchy-system-theme.ts"
  omarchy-theme-set-pi --activate
fi
