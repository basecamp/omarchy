echo "Add Tmux binding (Super+Alt+Return) to hypr/bindings.conf"

bindings_file="$HOME/.config/hypr/bindings.conf"

if [[ -f $bindings_file ]] && ! grep -qE '^bindd?\s*=\s*SUPER\s+ALT\s*,\s*RETURN' "$bindings_file"; then
  sed -i '1a bindd = SUPER ALT, RETURN, Tmux, exec, uwsm-app -- xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" tmux new' "$bindings_file"
fi
