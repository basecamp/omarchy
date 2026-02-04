#!/bin/bash

update-desktop-database ~/.local/share/applications

# Open all images with imv
xdg-mime default org.gnome.gThumb.desktop image/png
xdg-mime default org.gnome.gThumb.desktop image/jpeg
xdg-mime default org.gnome.gThumb.desktop image/gif
xdg-mime default org.gnome.gThumb.desktop image/webp
xdg-mime default org.gnome.gThumb.desktop image/bmp
xdg-mime default org.gnome.gThumb.desktop image/tiff

# Open PDFs with the Document Viewer
xdg-mime default xreader.desktop application/pdf

# Use Chromium as the default browser
# xdg-settings set default-web-browser chromium.desktop
# xdg-mime default chromium.desktop x-scheme-handler/http
# xdg-mime default chromium.desktop x-scheme-handler/https
xdg-settings set default-web-browser zen-browser.desktop
xdg-mime default zen-browser.desktop x-scheme-handler/http
xdg-mime default zen-browser.desktop x-scheme-handler/https

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
