echo "Disable user autostarts that compete with the supervised fcitx5 service"

# XDG autostart entries only mask another entry with the same filename. A user
# may therefore have an older, differently named entry that still launches
# fcitx5 alongside omarchy-fcitx5.service. The stray instance wins the D-Bus
# name race and leaves the Restart=always unit looping forever.
autostart_dir="$HOME/.config/autostart"
[[ -d $autostart_dir ]] || exit 0

affected=false

for desktop_file in "$autostart_dir"/*.desktop; do
  [[ -f $desktop_file ]] || continue
  grep -qxF '[Desktop Entry]' "$desktop_file" || continue

  in_desktop_entry=false
  exec_line=""
  hidden_present=false
  hidden_value=""
  while IFS= read -r line; do
    if [[ $line == "[Desktop Entry]" ]]; then
      in_desktop_entry=true
      continue
    elif [[ $line == \[*\] ]]; then
      $in_desktop_entry && break
      continue
    fi

    $in_desktop_entry || continue

    if [[ $line =~ ^[[:space:]]*Exec[[:space:]]*=(.*)$ ]]; then
      exec_line=${BASH_REMATCH[1]}
    elif [[ $line =~ ^[[:space:]]*Hidden[[:space:]]*=(.*)$ ]]; then
      hidden_present=true
      hidden_value=${BASH_REMATCH[1]}
    fi
  done <"$desktop_file"

  exec_line=${exec_line#"${exec_line%%[![:space:]]*}"}
  hidden_value=${hidden_value#"${hidden_value%%[![:space:]]*}"}
  hidden_value=${hidden_value%"${hidden_value##*[![:space:]]}"}

  if [[ $exec_line == \"* ]]; then
    executable=${exec_line#\"}
    executable=${executable%%\"*}
  else
    executable=${exec_line%%[[:space:]]*}
  fi

  [[ ${executable##*/} == "fcitx5" ]] || continue
  affected=true
  [[ $hidden_value == "true" ]] && continue

  if $hidden_present; then
    sed -i -E '/^\[Desktop Entry\][[:space:]]*$/,/^\[[^]]+\][[:space:]]*$/{s/^[[:space:]]*Hidden[[:space:]]*=.*$/Hidden=true/}' "$desktop_file"
  else
    sed -i '/^[[:space:]]*\[Desktop Entry\][[:space:]]*$/aHidden=true' "$desktop_file"
  fi
done

# Outside a graphical session the next login starts the sole remaining fcitx5
# through systemd. Inside one, replace the competing process immediately so the
# service stops flooding the journal and keeps the Compose table supervised.
if $affected && systemctl --user is-active --quiet graphical-session.target; then
  omarchy-restart-xcompose
fi
