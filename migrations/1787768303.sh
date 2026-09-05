echo "Enable native Wayland clipboard sharing in SPICE guests"

spice_port="${OMARCHY_SPICE_PORT:-/dev/virtio-ports/com.redhat.spice.0}"
[[ -e $spice_port ]] || exit 0

omarchy-pkg-add spice-vdagent

# Never leave the stock X11 agent connected beside the Wayland replacement.
# vdagentd accepts one session agent and disconnects both when they compete.
systemctl --user stop spice-vdagent.service >/dev/null 2>&1 || true
pkill -x spice-vdagent >/dev/null 2>&1 || true
global_state="$(systemctl --global is-enabled spice-vdagent.service 2>/dev/null || true)"
if [[ $global_state != "masked" ]]; then
  sudo systemctl --global mask spice-vdagent.service
fi

# Installing the package after the virtio device appeared cannot replay its
# udev add event, so activate the static socket explicitly for existing VMs.
if ! systemctl is-active --quiet spice-vdagentd.socket; then
  sudo systemctl start spice-vdagentd.socket
fi

unit_name=omarchy-vdagent.service
unit_source="$OMARCHY_PATH/default/systemd/user/$unit_name"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$unit_dir/$unit_name"

install -Dm644 "$unit_source" "$unit"
systemctl --user daemon-reload >/dev/null 2>&1 || true

# A TTY update may not have a live user manager. In that case, write the same
# wants link systemctl would create and let the next graphical login start it.
if ! systemctl --user enable "$unit_name" >/dev/null 2>&1; then
  wants_dir="$unit_dir/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn "../$unit_name" "$wants_dir/$unit_name"
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user restart "$unit_name"
fi
