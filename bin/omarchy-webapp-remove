#!/bin/bash

# omarchy:summary=Remove a web app desktop launcher
# omarchy:args=[name]

set -e

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
OLD_ICON_DIR="$HOME/.local/share/applications/icons"
DESKTOP_DIR="$HOME/.local/share/applications/"

# Always index the launchers, so removal deletes the file that was found rather
# than a path rebuilt from the displayed name. Installs predating the name
# validation could nest the launcher inside directories, and those are exactly
# the ones a reconstructed path cannot reach.
WEB_APP_PATHS=()
while IFS= read -r -d '' file; do
  if grep -q '^Exec=.*\(omarchy-launch-webapp\|omarchy-webapp-handler\).*' "$file"; then
    WEB_APPS+=("$(basename "${file%.desktop}")")
    WEB_APP_PATHS+=("$file")
  fi
done < <(find "$DESKTOP_DIR" -name '*.desktop' -print0 2>/dev/null)

# The launcher matching a chosen name, or empty when nothing was indexed under
# it (an app removed between the scan and the pick, say).
path_for_web_app() {
  local wanted="$1" i
  for i in "${!WEB_APPS[@]}"; do
    if [[ ${WEB_APPS[$i]} == "$wanted" ]]; then
      printf '%s\n' "${WEB_APP_PATHS[$i]}"
      return 0
    fi
  done
}

if (( $# == 0 )); then
  if ((${#WEB_APPS[@]})); then
    mapfile -t SORTED_WEB_APPS < <(printf '%s\n' "${WEB_APPS[@]}" | sort)
    APP_NAME=$(omarchy-menu-select "Select web app to remove" "${SORTED_WEB_APPS[@]}" -- --width 520 --maxheight 520)
  else
    echo "No web apps to remove."
    exit 1
  fi
else
  APP_NAME="$*"
fi

if [[ -z $APP_NAME ]]; then
  echo "You must select a web app to remove."
  exit 1
fi

icon_name=$(printf '%s\n' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')
desktop_file=$(path_for_web_app "$APP_NAME")
rm -f "${desktop_file:-$DESKTOP_DIR/$APP_NAME.desktop}"
rm -f "$ICON_DIR/$icon_name.png" "$ICON_DIR/$APP_NAME.png" "$OLD_ICON_DIR/$APP_NAME.png"

if [[ ${OMARCHY_REMOVE_NOTIFY:-true} != "false" ]]; then
  omarchy-notification-send -g  "Web app removed" "$APP_NAME"
fi
update-desktop-database "$DESKTOP_DIR" &>/dev/null
