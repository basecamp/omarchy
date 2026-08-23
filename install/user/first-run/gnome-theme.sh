gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"
# GNOME's default appmenu:close deletes Chrome's CSD min/max. Desktop Mode
# keeps minimize, maximize, and close on the client's own caption row.
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
