echo "Use current terminal shell cwd for new terminal working directories"

sed -i 's|bindd = SUPER, return, Terminal, exec, \$terminal|bindd = SUPER, return, Terminal, exec, $terminal --working-directory $(omarchy-cmd-terminal-cwd)|' ~/.config/hypr/bindings.conf