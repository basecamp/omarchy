echo "Add Tmux as an option with themed styling"

omarchy-pkg-add tmux

if [[ ! -f ~/.config/tmux/tmux.conf ]]; then
  mkdir -p ~/.config/tmux
  cp $OMARCHY_PATH/config/tmux/tmux.conf ~/.config/tmux/tmux.conf
  omarchy-theme-refresh
fi
