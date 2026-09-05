#!/bin/bash

# The system half is prepared by install/hardware/spice-vdagent.sh. By first
# run, UWSM has imported WAYLAND_DISPLAY into the user manager and the SPICE
# virtio channel has activated spice-vdagentd.socket.

set -euo pipefail

spice_port="${OMARCHY_SPICE_PORT:-/dev/virtio-ports/com.redhat.spice.0}"
[[ -e $spice_port ]] || exit 0

stock_state="$(systemctl --user is-enabled spice-vdagent.service 2>/dev/null || true)"
if [[ $stock_state != "masked" ]]; then
  echo "The stock SPICE X11 session agent is not masked; refusing to run two agents." >&2
  exit 1
fi

unit_name=omarchy-vdagent.service
unit_source="$OMARCHY_PATH/default/systemd/user/$unit_name"
unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit_name"

install -Dm644 "$unit_source" "$unit"
systemctl --user daemon-reload
systemctl --user enable --now "$unit_name"
