echo "Update tmux window navigation keybindings"

if [[ -f ~/.config/tmux/tmux.conf ]]; then
  cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.bak.$(date +%s)
fi

cp $OMARCHY_PATH/config/tmux/tmux.conf ~/.config/tmux/tmux.conf
