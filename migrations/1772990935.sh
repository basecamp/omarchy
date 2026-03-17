echo "Enable extended-keys in tmux configuration"

if [[ -f ~/.config/tmux/tmux.conf ]]; then
  if ! grep -q "set -s extended-keys on" ~/.config/tmux/tmux.conf; then
    # Locate '# General' and a:ppend
    sed -i '/# General/a set -s extended-keys on' ~/.config/tmux/tmux.conf

    omarchy-restart-tmux
  fi
fi
