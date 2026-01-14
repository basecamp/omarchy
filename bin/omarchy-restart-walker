#!/bin/bash

restart_services() {
  if systemctl --user is-enabled elephant.service &>/dev/null; then
    systemctl --user restart elephant.service
  fi

  if systemctl --user is-enabled app-walker@autostart.service &>/dev/null; then
    systemctl --user restart app-walker@autostart.service
  else
    echo -e "\e[31mUnable to restart Walker -- RESTART MANUALLY\e[0m"
  fi
}

if [[ $EUID -eq 0 ]]; then
  SCRIPT_OWNER=$(stat -c '%U' "$0")
  USER_UID=$(id -u "$SCRIPT_OWNER")
  systemd-run --uid="$SCRIPT_OWNER" --setenv=XDG_RUNTIME_DIR="/run/user/$USER_UID" \
    bash -c "$(declare -f restart_services); restart_services"
else
  restart_services
fi
