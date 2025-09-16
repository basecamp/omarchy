echo "Ensure $TERMINAL is set in uwsm env so entire system can rely on it"

if ! grep -q "export TERMINAL" ~/.config/uwsm/env; then
  omarchy-refresh-config uwsm/env
  omarchy-state set relaunch-required
fi
