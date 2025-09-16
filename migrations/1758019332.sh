echo "Ensure $TERMINAL is set in uwsm env so entire system can rely on it"

omarchy-refresh-config uwsm/env
omarchy-state set relaunch-required
