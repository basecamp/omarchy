# The stock SPICE session agent only exposes an X11 clipboard. Install the
# daemon package when the guest has a SPICE virtio channel, but mask only its
# per-session X11 agent; omarchy-vdagent replaces that half under Wayland.
spice_port="${OMARCHY_SPICE_PORT:-/dev/virtio-ports/com.redhat.spice.0}"

if [[ -e $spice_port ]]; then
  omarchy-pkg-add spice-vdagent
  systemctl --global mask spice-vdagent.service
fi
