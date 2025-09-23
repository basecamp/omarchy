#!/usr/bin/env bash

BOLD='\e[1m'
GREEN='\e[92m'
YELLOW='\e[93m'
RESET='\e[0m'

print_info() {
  echo -ne "${BOLD}${YELLOW}$1${RESET}\n"
}

print_choice() {
  echo -ne "${BOLD}${GREEN}>> $1${RESET}\n\n"
}

install_shell() {
  shell=$1
  if ! command -v "$shell" >/dev/null 2>&1; then
    print_info "$shell not found. Installing..."
    if command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm "$shell"
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "$shell"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$shell"
    else
      print_info "No supported package manager found. Please install $shell manually."
      exit 1
    fi
  fi
}

print_info "Choose your user's default shell:"
echo "1. bash"
echo "2. fish"
echo "3. zsh"
echo "4. quit"

read -p "Enter the number of your preferred shell: " choice

case $choice in
1)
  install_shell bash
  chsh -s "$(command -v bash)"
  print_choice "Shell choice: bash"
  printf '%s\n' "If default shell was changed, you will need to logout and log back in for change to take effect."
  ;;
2)
  install_shell fish
  chsh -s "$(command -v fish)"
  print_choice "Shell choice: fish"
  printf '%s\n' "If default shell was changed, you will need to logout and log back in for change to take effect."
  ;;
3)
  install_shell zsh
  chsh -s "$(command -v zsh)"
  print_choice "Shell choice: zsh"
  printf '%s\n' "If default shell was changed, you will need to logout and log back in for change to take effect."
  ;;
4)
  echo "User has chosen to quit program."
  exit 1
  ;;
*)
  echo "Invalid choice. Please try again."
  exit 1
  ;;
esac
