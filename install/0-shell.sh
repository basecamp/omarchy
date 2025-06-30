#!/bin/bash

# Ask the user for their preferred shell
SHELL_CHOICE=$(gum choose "bash" "zsh" --header "Which shell would you like to use?")

# Store the choice
mkdir -p ~/.config/omarchy
echo "$SHELL_CHOICE" >~/.config/omarchy/shell_choice

# If zsh is chosen, check if it's installed and install it if not
if [ "$SHELL_CHOICE" = "zsh" ]; then
  if ! command -v zsh &>/dev/null; then
    sudo pacman -S --needed --noconfirm zsh
  fi
  sudo usermod --shell /bin/zsh "$USER"
fi
