#!/bin/bash
ansi_art='                                                                          
   ▄████████ ███    █▄      ███        ▄████████    ▄████████    ▄█   ▄█▄ ▄██   ▄   
  ███    ███ ███    ███ ▀█████████▄   ███    ███   ███    ███   ███ ▄███▀ ███   ██▄ 
  ███    ███ ███    ███    ▀███▀▀██   ███    ███   ███    ███   ███▐██▀   ███▄▄▄███ 
  ███    ███ ███    ███     ███   ▀   ███    ███  ▄███▄▄▄▄██▀  ▄█████▀    ▀▀▀▀▀▀███ 
▀███████████ ███    ███     ███     ▀███████████ ▀▀███▀▀▀▀▀   ▀▀█████▄    ▄██   ███ 
  ███    ███ ███    ███     ███       ███    ███ ▀███████████   ███▐██▄   ███   ███ 
  ███    ███ ███    ███     ███       ███    ███   ███    ███   ███ ▀███▄ ███   ███ 
  ███    █▀  ████████▀     ▄████▀     ███    █▀    ███    ███   ███   ▀█▀  ▀█████▀  
                                                   ███    ███   ▀                   '

clear
echo -e "\n$ansi_art\n"

sudo pacman -Sy --noconfirm --needed git

echo -e "\nCloning Autarky..."
rm -rf ~/.local/share/autarky/
git clone https://github.com/frivasa/autarky.git ~/.local/share/autarky >/dev/null

echo -e "\nInstallation starting..."
source ~/.local/share/autarky/install.sh
