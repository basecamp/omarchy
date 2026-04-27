gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal custom
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal custom-local-command 'sh -c '\''[[ "$(xdg-terminal-exec --print-id)" = com.mitchellh.ghostty.desktop ]] && exec uwsm-app -- ghostty --gtk-single-instance=false --working-directory="$1" || exec uwsm-app -- xdg-terminal-exec --dir="$1"'\'' sh "%s"'
