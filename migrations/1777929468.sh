echo "Enable middle-click primary paste for GTK/Chromium-family apps (Ghostty, Brave, Chromium)"

if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true
fi
