echo "Configure Claude Code install method for pacman-based installation"

if command -v claude &>/dev/null && [ -f ~/.claude.json ]; then
  if grep -q '"installMethod": "unknown"' ~/.claude.json; then
    sed -i 's/"installMethod": "unknown"/"installMethod": "native"/' ~/.claude.json
  fi
fi
