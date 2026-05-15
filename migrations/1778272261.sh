echo "Stop naming new Super+Alt+Return tmux sessions Work"

bindings_file="$HOME/.config/hypr/bindings.conf"

if [[ -f $bindings_file ]] && grep -qF "tmux attach || tmux new -s Work" "$bindings_file"; then
  sed -i 's/tmux attach || tmux new -s Work/tmux attach || tmux new/' "$bindings_file"
fi
