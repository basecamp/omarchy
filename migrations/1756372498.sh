echo "Add eza themeing"

mkdir -p ~/.config/eza

if [ -f ~/.config/omarchy/current/theme/eza.yml ]; then
  ln -snf ~/.config/omarchy/current/theme/eza.yml ~/.config/eza/theme.yml
fi

