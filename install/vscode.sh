#!/bin/bash

yay -S --needed visual-studio-code-bin --noconfirm

mkdir -p ~/.config/Code/User
cp ~/.local/share/omarchy/config/vscode/settings.json ~/.config/Code/User/settings.json

# Install default supported themes
code --install-extension enkia.tokyo-night

# Install VIM extension for vscode 
code --install-extension vscodevim.vim