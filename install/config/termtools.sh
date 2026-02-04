#!/bin/bash

echo "Installing/Configuring keyd, Starship, and Tmux"

# Install zsh and related packages
sudo pacman -S --noconfirm --needed starship tmux keyd
# yay -S --noconfirm --needed zsh zsh-syntax-highlighting zsh-autosuggestions zsh-vi-mode kitty
yay -S --noconfirm --needed kitty

# enable plugins for tmux
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# copy config and enable keyd bindings
sudo mkdir -p /etc/keyd
sudo cp ~/.local/share/autarky/default/default.conf /etc/keyd/default.conf
if ! systemctl is-enabled keyd.service | grep -q enabled; then
  sudo systemctl enable keyd
fi

# Change default shell to zsh
# if [ "$SHELL" != "$(which zsh)" ]; then
#   chsh -s $(which zsh)
#   echo "Default shell changed to zsh. You may need to log out and back in for this to take effect."
# fi
