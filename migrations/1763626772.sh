echo "Make hackerman available as new theme"

if [[ ! -L ~/.config/omarchy/themes/hackerman ]]; then
  rm -rf ~/.config/omarchy/themes/hackerman
  ln -nfs ~/.local/share/omarchy/themes/hackerman ~/.config/omarchy/themes/
fi
