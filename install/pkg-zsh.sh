#!/bin/bash
set -e

echo "Installing zsh and zsh plugins..."

omarchy-pkg-add zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions

echo ""
echo "Optional: Install fzf-tab for fzf-powered completions (AUR)"
echo "  yay -S fzf-tab"
echo ""
echo "To switch to zsh:"
echo "  1. cp ~/.local/share/omarchy/default/zshrc ~/.zshrc"
echo "  2. chsh -s /bin/zsh"
echo "  3. Log out and back in"
