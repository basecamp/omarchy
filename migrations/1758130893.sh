#!/bin/bash

echo "Update development environment and add new productivity tools"

# Update existing packages to latest versions
echo "Updating core development packages..."
sudo pacman -Syu --noconfirm --needed \
  neovim \
  lazygit \
  ripgrep \
  fd \
  bat \
  eza \
  dust \
  zoxide

# Install new productivity tools
echo "Installing additional productivity tools..."
omarchy-pkg-install \
  git-delta \
  tokei \
  bottom \
  procs \
  bandwhich \
  hyperfine \
  sd

# Update Neovim configuration to include new LSP servers
echo "Refreshing Neovim configuration..."
omarchy-refresh-config nvim

# Update terminal configuration for better development experience
echo "Updating terminal configurations..."
omarchy-refresh-config alacritty

# Refresh Git configuration with new aliases
echo "Updating Git configuration..."
if [[ -f ~/.gitconfig ]]; then
  # Add useful Git aliases if they don't exist
  if ! grep -q "alias.st" ~/.gitconfig; then
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.df diff
    git config --global alias.lg "log --oneline --graph --decorate --all"
  fi
fi

# Update shell configuration for new tools
echo "Updating shell configurations..."
if [[ -f ~/.config/fish/config.fish ]]; then
  # Ensure zoxide is initialized in fish
  if ! grep -q "zoxide init" ~/.config/fish/config.fish; then
    echo "zoxide init fish | source" >> ~/.config/fish/config.fish
  fi
fi

# Refresh application launcher to include new tools
echo "Refreshing application launcher..."
omarchy-restart-walker

# Update system search database
echo "Updating locate database..."
sudo updatedb 2>/dev/null || true

echo "Development environment migration completed successfully!"
echo "New tools available: git-delta, tokei, bottom, procs, bandwhich, hyperfine, sd"
echo "Git aliases added: st, co, br, ci, df, lg"
