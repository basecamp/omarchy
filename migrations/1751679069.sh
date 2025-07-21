echo "Install ffmpegthumbnailer for video thumbnails in the file manager"

if ! command -v ffmpegthumbnailer &>/dev/null; then
  yay -S --noconfirm --needed ffmpegthumbnailer
fi
