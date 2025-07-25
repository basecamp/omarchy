#!/bin/bash

# Need gum to query for input
yay -S --noconfirm --needed gum python-terminaltexteffects

# Configure identification
clear
tte -i ~/.local/share/omarchy/logo.txt --frame-rate 120 expand
echo -e "\nEnter identification for git and autocomplete..."
export OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ")
export OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ")
