echo "Create ~/Wallpapers directory for global wallpaper collection"

if [[ -d "$HOME/Wallpapers" ]]; then
  :
elif [[ -e "$HOME/Wallpapers" ]]; then
  echo "Skipping ~/Wallpapers creation: $HOME/Wallpapers exists but is not a directory"
else
  mkdir -p "$HOME/Wallpapers"
fi
