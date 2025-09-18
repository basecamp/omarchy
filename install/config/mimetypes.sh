omarchy-refresh-applications
update-desktop-database ~/.local/share/applications

# Open all images with imv
xdg-mime default imv.desktop image/png
xdg-mime default imv.desktop image/jpeg
xdg-mime default imv.desktop image/gif
xdg-mime default imv.desktop image/webp
xdg-mime default imv.desktop image/bmp
xdg-mime default imv.desktop image/tiff

# Open PDFs with the Document Viewer
xdg-mime default org.gnome.Evince.desktop application/pdf

# Use Chromium as the default browser
xdg-settings set default-web-browser chromium.desktop
xdg-mime default chromium.desktop x-scheme-handler/http
xdg-mime default chromium.desktop x-scheme-handler/https

# Open video files with mpv
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

# Open audio files with mpv
xdg-mime default mpv.desktop audio/mpeg
xdg-mime default mpv.desktop audio/x-wav
xdg-mime default mpv.desktop audio/ogg
xdg-mime default mpv.desktop audio/flac
xdg-mime default mpv.desktop audio/aac
xdg-mime default mpv.desktop audio/x-m4a
xdg-mime default mpv.desktop audio/mp4

# Open text files with nvim
xdg-mime default nvim.desktop text/plain

# Open subtitles with nvim
xdg-mime default nvim.desktop text/x-microdvd
xdg-mime default nvim.desktop text/x-srt

# Open markdown and code files with nvim
xdg-mime default nvim.desktop text/markdown
xdg-mime default nvim.desktop text/x-python
xdg-mime default nvim.desktop text/x-javascript
xdg-mime default nvim.desktop application/json
xdg-mime default nvim.desktop text/csv

# Open archives with pcmanfm
xdg-mime default pcmanfm.desktop application/zip
xdg-mime default pcmanfm.desktop application/x-tar
xdg-mime default pcmanfm.desktop application/gzip
xdg-mime default pcmanfm.desktop application/x-7z-compressed