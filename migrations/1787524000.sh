echo "Restore min/max/close on Chrome CSD; GNOME appmenu:close had deleted them"

gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

for gtk_ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  mkdir -p "$(dirname "$gtk_ini")"
  if [[ -f $gtk_ini ]] && grep -q '^gtk-decoration-layout=' "$gtk_ini"; then
    sed -i 's/^gtk-decoration-layout=.*/gtk-decoration-layout=:minimize,maximize,close/' "$gtk_ini"
  elif [[ -f $gtk_ini ]]; then
    if ! grep -q '^\[Settings\]' "$gtk_ini"; then
      printf '\n[Settings]\n' >>"$gtk_ini"
    fi
    printf 'gtk-decoration-layout=:minimize,maximize,close\n' >>"$gtk_ini"
  else
    printf '[Settings]\ngtk-decoration-layout=:minimize,maximize,close\n' >"$gtk_ini"
  fi
done
