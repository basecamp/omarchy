#!/bin/bash

yay -S --noconfirm --needed \
  wget curl unzip inetutils impala \
  fd eza fzf ripgrep zoxide bat jq \
  wl-clipboard fastfetch btop \
  man tldr less whois plocate bash-completion \
  alacritty

# Optional: Install Kitty terminal for enhanced features
# Kitty provides advanced features like image display, better Unicode support,
# and superior terminal graphics protocol support
echo "Installing Kitty terminal (optional but recommended for enhanced features)..."
yay -S --noconfirm --needed kitty
