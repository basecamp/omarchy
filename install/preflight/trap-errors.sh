#!/bin/bash

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo
  echo "This command halted with exit code $?:"
  echo "$BASH_COMMAND"
  echo
  echo "Get help from the community via QR code or at https://discord.gg/tXFUdasqhY"
  echo "                                 "
  echo "    █▀▀▀▀▀█ ▄ ▄ ▀▄▄▄█ █▀▀▀▀▀█    "
  echo "    █ ███ █ ▄▄▄▄▀▄▀▄▀ █ ███ █    "
  echo "    █ ▀▀▀ █ ▄█  ▄█▄▄▀ █ ▀▀▀ █    "
  echo "    ▀▀▀▀▀▀▀ ▀▄█ █ █ █ ▀▀▀▀▀▀▀    "
  echo "    ▀▀█▀▀▄▀▀▀▀▄█▀▀█  ▀ █ ▀ █     "
  echo "    █▄█ ▄▄▀▄▄ ▀ ▄ ▀█▄▄▄▄ ▀ ▀█    "
  echo "    ▄ ▄▀█ ▀▄▀▀▀▄ ▄█▀▄█▀▄▀▄▀█▀    "
  echo "    █ ▄▄█▄▀▄█ ▄▄▄  ▀ ▄▀██▀ ▀█    "
  echo "    ▀ ▀   ▀ █ ▀▄  ▀▀█▀▀▀█▄▀      "
  echo "    █▀▀▀▀▀█ ▀█  ▄▀▀ █ ▀ █▄▀██    "
  echo "    █ ███ █ █▀▄▄▀ █▀███▀█▄██▄    "
  echo "    █ ▀▀▀ █ ██  ▀ █▄█ ▄▄▄█▀ █    "
  echo "    ▀▀▀▀▀▀▀ ▀ ▀ ▀▀▀  ▀ ▀▀▀▀▀▀    "
  echo "                                 "

  if command -v gum >/dev/null && gum confirm "Retry installation?"; then
    bash ~/.local/share/omarchy/install.sh
  else
    echo "You can retry later by running: bash ~/.local/share/omarchy/install.sh"
  fi
}

trap catch_errors ERR
