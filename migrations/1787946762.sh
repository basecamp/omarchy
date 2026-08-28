echo "Stop forcing the Qt platform in the current graphical session"

user_manager_socket="${XDG_RUNTIME_DIR:-/run/user/$UID}/systemd/private"
if ! manager_environment=$(systemctl --user show-environment 2>&1); then
  if [[ -S $user_manager_socket ]]; then
    echo "Could not reach the running user service manager: $manager_environment"
    echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
    exit 1
  fi

  # A new user manager and D-Bus activation environment will start without the
  # removed default at the next login.
  exit 0
fi

if ! error=$(systemctl --user unset-environment QT_QPA_PLATFORM 2>&1); then
  echo "Could not clear QT_QPA_PLATFORM from the user service manager: $error"
  echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
  exit 1
fi

if ! graphical_state=$(systemctl --user show --property=ActiveState --value graphical-session.target 2>&1); then
  echo "Could not inspect graphical-session.target: $graphical_state"
  echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
  exit 1
fi

# D-Bus has no unset operation for activation variables. An empty value is
# equivalent to no override for Qt and replaces the stale fallback list.
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  if ! error=$(dbus-update-activation-environment QT_QPA_PLATFORM= 2>&1); then
    echo "Could not clear QT_QPA_PLATFORM from the D-Bus activation environment: $error"
    echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
    exit 1
  fi
elif [[ $graphical_state == "active" ]]; then
  echo "Could not reach the D-Bus activation environment in the graphical session."
  echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
  exit 1
fi

# Removing hl.env() from the config does not mutate the already-running
# compositor process. Empty the value there so future keybind launches do not
# inherit the stale fallback list either.
if [[ $graphical_state == "active" ]]; then
  if ! error=$(hyprctl eval 'hl.env("QT_QPA_PLATFORM", "")' 2>&1); then
    echo "Could not clear QT_QPA_PLATFORM from the running Hyprland session: $error"
    echo "The Qt platform environment cleanup will be retried by omarchy-migrate."
    exit 1
  fi
fi

if pgrep -x steam >/dev/null 2>&1; then
  echo "Steam is still running with the old Qt platform value. Fully exit and restart Steam before launching SteamVR."
fi
