#!/bin/bash

echo "Quote terminal cwd binding in Hyprland"

HYPR_BINDINGS_FILE="$HOME/.config/hypr/bindings.conf"
TARGET='bindd = SUPER, return, Terminal, exec, $terminal --working-directory="$(omarchy-cmd-terminal-cwd)"'

if grep -Fq "$TARGET" "$HYPR_BINDINGS_FILE"; then
  exit 0
fi

if grep -Fq 'bindd = SUPER, return, Terminal, exec, $terminal --working-directory=$(omarchy-cmd-terminal-cwd)' "$HYPR_BINDINGS_FILE"; then
  sed -i 's|bindd = SUPER, return, Terminal, exec, \$terminal --working-directory=\$(omarchy-cmd-terminal-cwd)|bindd = SUPER, return, Terminal, exec, \$terminal --working-directory="$(omarchy-cmd-terminal-cwd)"|' "$HYPR_BINDINGS_FILE"
elif grep -Fq 'bindd = SUPER, return, Terminal, exec, $terminal --working-directory $(omarchy-cmd-terminal-cwd)' "$HYPR_BINDINGS_FILE"; then
  sed -i 's|bindd = SUPER, return, Terminal, exec, \$terminal --working-directory \$(omarchy-cmd-terminal-cwd)|bindd = SUPER, return, Terminal, exec, \$terminal --working-directory="$(omarchy-cmd-terminal-cwd)"|' "$HYPR_BINDINGS_FILE"
elif grep -Fq 'bindd = SUPER, return, Terminal, exec, $terminal' "$HYPR_BINDINGS_FILE"; then
  sed -i '/bindd = SUPER, return, Terminal, exec, \$terminal/ s|$| --working-directory="$(omarchy-cmd-terminal-cwd)"|' "$HYPR_BINDINGS_FILE"
fi
