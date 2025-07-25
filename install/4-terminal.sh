#!/bin/bash

show_logo
show_subtext "Let's install basic terminal tools..."

yay -S --noconfirm --needed \
  wget curl unzip inetutils impala \
  fd eza fzf ripgrep zoxide bat jq \
  wl-clipboard fastfetch btop \
  man tldr less whois plocate bash-completion \
  alacritty
