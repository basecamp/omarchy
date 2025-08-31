echo "Add eza config directory"

mkdir -p ~/.config/eza
# not all themes have eza config, only link if it exists
if [ -f ~/.config/omarchy/current/theme/eza-theme.yml ]; then
  ln -snf ~/.config/omarchy/current/theme/eza-theme.yml ~/.config/eza/theme.yml
fi