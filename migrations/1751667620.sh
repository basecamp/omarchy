echo "Switching from vlc to mpv for the default video player"
if ! command -v mpv &>/dev/null; then
  sudo pacman -Rns --noconfirm vlc
  rm ~/.local/share/applications/vlc.desktop
  sudo pacman -S --noconfirm mpv
  xdg-mime default mpv.desktop video/mp4
  xdg-mime default mpv.desktop video/x-msvideo
  xdg-mime default mpv.desktop video/x-matroska
  xdg-mime default mpv.desktop video/x-flv
  xdg-mime default mpv.desktop video/x-ms-wmv
  xdg-mime default mpv.desktop video/mpeg
  xdg-mime default mpv.desktop video/ogg
  xdg-mime default mpv.desktop video/webm
  xdg-mime default mpv.desktop video/quicktime
  xdg-mime default mpv.desktop video/3gpp
  xdg-mime default mpv.desktop video/3gpp2
  xdg-mime default mpv.desktop video/x-ms-asf
  xdg-mime default mpv.desktop video/x-ogm+ogg
  xdg-mime default mpv.desktop video/x-theora+ogg
  xdg-mime default mpv.desktop application/ogg
fi
