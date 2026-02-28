# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc

# Use default zshrc from Omarchy (if zsh is installed)
if command -v zsh &> /dev/null; then
  cp ~/.local/share/omarchy/default/zshrc ~/.zshrc
fi
