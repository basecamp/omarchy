OMARCHY_DESCRIPTION="GNOME Theme Settings"

omarchy_verify() {
  gsettings get org.gnome.desktop.interface gtk-theme &>/dev/null || add_error "Cannot access GTK theme setting"
  gsettings get org.gnome.desktop.interface color-scheme &>/dev/null || add_error "Cannot access color scheme setting"
  gsettings get org.gnome.desktop.interface icon-theme &>/dev/null || add_error "Cannot access icon theme setting"

  [[ -d /usr/share/icons ]] || add_error "Icon themes directory missing"
}
