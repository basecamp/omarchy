echo "Use current terminal shell cwd for new terminal working directories"

# Handle the case where no --working-directory exists yet
sed -i 's|bindd = SUPER, return, Terminal, exec, \$terminal$|bindd = SUPER, return, Terminal, exec, $terminal --working-directory=$(omarchy-cmd-terminal-cwd)|' ~/.config/hypr/bindings.conf

# Handle the case where --working-directory exists without equals sign
sed -i 's|bindd = SUPER, return, Terminal, exec, \$terminal --working-directory \$(.*)|bindd = SUPER, return, Terminal, exec, $terminal --working-directory=$(omarchy-cmd-terminal-cwd)|' ~/.config/hypr/bindings.conf
