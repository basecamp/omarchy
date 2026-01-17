#!/bin/bash

# Returns the current working directory of the active terminal window,
# so a new terminal window can be started in the same directory.

# Go from current active terminal to its child shell process and run cwd there
terminal_pid=$(hyprctl activewindow | awk '/pid:/ {print $2}')
shell_pid=$(pgrep -P "$terminal_pid" | tail -n1)

if [[ -n $shell_pid ]]; then
  cwd=$(readlink -f "/proc/$shell_pid/cwd" 2>/dev/null)
  shell=$(readlink -f "/proc/$shell_pid/exe" 2>/dev/null)

  # Check if $shell is a valid shell and $cwd is a directory.
  if grep -qs "$shell" /etc/shells && [[ -d $cwd ]]; then
    echo "$cwd"
  else
    echo "$HOME"
  fi
else
  echo "$HOME"
fi
