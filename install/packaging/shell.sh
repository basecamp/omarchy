#!/bin/bash
set -e

echo "Installing zsh and zsh plugins..."

omarchy-pkg-add zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions

echo ""
echo "Zsh and plugins installed successfully!"
echo ""
echo "To switch to zsh as your default shell, run:"
echo "  omarchy-shell-switch zsh"
