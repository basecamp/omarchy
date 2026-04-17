omarchy-refresh-applications
update-desktop-database ~/.local/share/applications

# Open directories in file manager
omarchy-defaults apply filemanager org.gnome.Nautilus.desktop

# Open all images with imv
omarchy-defaults apply image imv.desktop

# Open PDFs with the Document Viewer
omarchy-defaults apply pdf org.gnome.Evince.desktop

# Use Chromium as the default browser
omarchy-defaults apply browser chromium.desktop

# Open video and audio files with mpv
omarchy-defaults apply video mpv.desktop
omarchy-defaults apply audio mpv.desktop

# Use Hey for mailto: links
omarchy-defaults apply mail HEY.desktop

# Open text files with nvim
omarchy-defaults apply editor nvim
