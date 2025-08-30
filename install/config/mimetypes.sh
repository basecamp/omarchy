#!/bin/bash

omarchy-refresh-applications
update-desktop-database ~/.local/share/applications

# Open all images with ristretto
xdg-mime default ristretto.desktop image/png
xdg-mime default ristretto.desktop image/jpeg
xdg-mime default ristretto.desktop image/gif
xdg-mime default ristretto.desktop image/webp
xdg-mime default ristretto.desktop image/bmp
xdg-mime default ristretto.desktop image/tiff

# Open PDFs with the Document Viewer
xdg-mime default org.gnome.Evince.desktop application/pdf

# Use Chromium as the default browser
xdg-settings set default-web-browser vivaldi.desktop
xdg-mime default vivaldi.desktop x-scheme-handler/http
xdg-mime default vivaldi.desktop x-scheme-handler/https

# Open video files with vlc
xdg-mime default vlc.desktop video/mp4
xdg-mime default vlc.desktop video/x-msvideo
xdg-mime default vlc.desktop video/x-matroska
xdg-mime default vlc.desktop video/x-flv
xdg-mime default vlc.desktop video/x-ms-wmv
xdg-mime default vlc.desktop video/mpeg
xdg-mime default vlc.desktop video/ogg
xdg-mime default vlc.desktop video/webm
xdg-mime default vlc.desktop video/quicktime
xdg-mime default vlc.desktop video/3gpp
xdg-mime default vlc.desktop video/3gpp2
xdg-mime default vlc.desktop video/x-ms-asf
xdg-mime default vlc.desktop video/x-ogm+ogg
xdg-mime default vlc.desktop video/x-theora+ogg
xdg-mime default vlc.desktop application/ogg
