echo "Make new Osaka Jade theme available as new default"

if [[ ! -L ~/.config/omarchy/themes/osaka-jade ]]; then
  rm -rf ~/.local/share/omarchy/themes/osaka-jade
  ln -nfs ~/.local/share/omarchy/themes/osaka-jade ~/.config/omarchy/themes/osaka-jade
fi
