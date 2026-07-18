# Nudge text down slightly on the Dell XPS 13 (DX13260, 2026), whose 2560x1600
# panel renders the default scaling a touch large.
if omarchy-hw-match "DX13260"; then
  gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
fi
