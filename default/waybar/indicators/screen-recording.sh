PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omarchy-screenrecord.pid"

if [[ -f "$PIDFILE" ]] && kill -0 $(head -n 1 "$PIDFILE") 2>/dev/null; then
  echo '{"text": "󰻂", "tooltip": "Stop recording", "class": "active"}'
else
  echo '{"text": ""}'
fi
