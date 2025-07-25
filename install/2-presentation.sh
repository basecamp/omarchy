#!/bin/bash

# Need gum to query for input
yay -S --noconfirm --needed gum python-terminaltexteffects

show_logo() {
  clear
  tte -i ~/.local/share/omarchy/logo.txt --frame-rate 120 expand
  echo -e ""
}

show_subtext() {
  echo "$1" | tte --frame-rate 640 wipe
  echo -e ""
}
