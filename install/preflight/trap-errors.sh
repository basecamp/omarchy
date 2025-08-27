#!/bin/bash

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo
  echo "This command halted with exit code $?:"
  echo "$BASH_COMMAND"
  echo
  echo "Get help from the community via QR code or at https://dc.omarchy.org"
  echo "                               "
  echo "    ███████████████████████████"
  echo "    █ ▄▄▄▄▄ █▀▀ ██▄█ ▀█ ▄▄▄▄▄ █"
  echo "    █ █   █ █▄▀██▀█▄█▄█ █   █ █"
  echo "    █ █▄▄▄█ █ ▄ █ █▄  █ █▄▄▄█ █"
  echo "    █▄▄▄▄▄▄▄█ █ ▀▄█▄█ █▄▄▄▄▄▄▄█"
  echo "    █  █▄█▀▄ ▀▀█  ▄▄█ ▀ ▄▄█▄▄▀█"
  echo "    ██▀▀█ ▄▄█▀▀▀  ▀███▀ ▄ ██▄▄█"
  echo "    █▄▀ ▀▀▄▄▀ █▄ █▄▀██▀ ▀█ ▀▄ █"
  echo "    █▄▀▀█▄▀▄  █  █ █▀█▀▀▄ █▄▀▄█"
  echo "    █▄▄█▄█▄▄█▀ ▄█ ▀▀▀ ▄▄▄  ▄█▀█"
  echo "    █ ▄▄▄▄▄ █▄▄▀▄ ▄▀▄ █▄█  ▀ ▄█"
  echo "    █ █   █ █▀▀▀▀▄▄██▄▄▄   ▀▄██"
  echo "    █ █▄▄▄█ █▀▀▀▀▄▀█  ▀▀▄▄▀▄█▄█"
  echo "    █▄▄▄▄▄▄▄█▄▄▄▄▄█▄▄▄▄█▄███▄▄█"

  echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
}

trap catch_errors ERR
