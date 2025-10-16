#!/bin/bash

if [[ -f ~/.config/alacritty/alacritty.toml ]]; then
  touch ~/.config/alacritty/alacritty.toml
fi

killall -SIGUSR1 kitty
killall -SIGUSR2 ghostty
