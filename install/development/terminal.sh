#!/bin/zsh
sudo pacman -S --noconfirm --needed udisks2 usb_modeswitch tree reflector

yay -S --noconfirm --needed \
  wget curl unzip inetutils impala \
  fd eza fzf ripgrep bat jq \
  wl-clipboard fastfetch btop \
  man tldr less whois plocate

