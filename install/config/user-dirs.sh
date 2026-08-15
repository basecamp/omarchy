mkdir -p ~/Downloads ~/Pictures ~/Videos ~/.config/gtk-3.0

xdg-user-dirs-update --set TEMPLATES "$HOME"
xdg-user-dirs-update --set PUBLICSHARE "$HOME"
xdg-user-dirs-update --set DESKTOP "$HOME"

rmdir ~/Templates ~/Public ~/Desktop 2>/dev/null || true

touch ~/.config/gtk-3.0/bookmarks
for dir in Downloads Projects Pictures Videos; do
  printf 'file://%s/%s %s\n' "$HOME" "$dir" "$dir" >>~/.config/gtk-3.0/bookmarks
done
