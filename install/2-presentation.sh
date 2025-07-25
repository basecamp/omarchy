#!/bin/bash

# Need gum to query for input
yay -S --noconfirm --needed gum python-terminaltexteffects

show_logo() {
  clear
  tte -i ~/.local/share/omarchy/logo.txt --frame-rate ${2:-120} ${1:-expand}
  echo -e ""
}

show_subtext() {
  echo "$1" | tte --frame-rate ${3:-640} ${2:-wipe}
  echo -e ""
}
