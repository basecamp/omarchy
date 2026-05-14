#!/bin/bash

echo "Migrating to use omarchy-launch-webapp and omarchy-launch-browser"
for desktop_file in ~/.local/share/applications/*.desktop; do
  if grep -q 'Exec=chromium --new-window --ozone-platform=wayland --app=' "$desktop_file"; then
    url=$(grep '^Exec=' "$desktop_file" | sed -n 's/.*--app="\?\([^"]*\)"\?.*/\1/p')

    if [[ -n $url ]]; then
      sed -i "s|^Exec=.*|Exec=omarchy-launch-webapp \"$url\"|" "$desktop_file"
    fi
  fi
done


