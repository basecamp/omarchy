#!/bin/bash

echo "Install tmux-powerkit plugin"
if [[ ! -d "$HOME/.config/tmux/plugins/tmux-powerkit" ]]; then
  mkdir -p "$HOME/.config/tmux/plugins"
  git clone --depth 1 \
    https://github.com/fabioluciano/tmux-powerkit.git \
    "$HOME/.config/tmux/plugins/tmux-powerkit"
fi
