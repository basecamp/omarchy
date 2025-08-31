echo "Use current terminal shell cwd for new terminal working directories"

if ! grep -q "working-directory" ~/.config/hypr/bindings.conf; then
  sed -i '/bindd = SUPER, return, Terminal, exec, \$terminal/ s|$| --working-directory=$(omarchy-cmd-terminal-cwd)|' ~/.config/hypr/bindings.conf
fi
