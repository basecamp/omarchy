#!/bin/bash
sed -i 's|readlink -f "/proc/$shell_pid/cwd" 2>/dev/null|readlink -f "/proc/$shell_pid/cwd" 2>/dev/null \|\| echo "$HOME"|' $OMARCHY_PATH/bin/omarchy-cmd-terminal-cwd
