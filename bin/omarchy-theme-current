#!/bin/bash

# omarchy:summary=Show current theme
# omarchy:examples=omarchy theme current

THEME_NAME_PATH="$HOME/.local/state/omarchy/current/theme.name"

if [[ -f $THEME_NAME_PATH ]]; then
  sed -E 's/(^|-)([a-z])/\1\u\2/g; s/-/ /g' "$THEME_NAME_PATH"
else
  echo "Unknown"
fi
