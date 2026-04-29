# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc

# If using zsh, also copy zshrc
if [[ -n "$ZSH_VERSION" ]] || grep -q zsh "$SHELL" 2>/dev/null; then
  cp ~/.local/share/omarchy/default/zsh/rc ~/.zshrc
fi
