# Disable hardware cursors when the nouveau driver is in use.
#
# The nouveau DRM driver does not display the hardware cursor plane on many
# older NVIDIA GPUs (e.g. Apple's GeForce 320M / MCP89 in the 2010 Mac mini),
# leaving the mouse pointer invisible on the physical display under Hyprland.
# Forcing software cursors makes the pointer render correctly.
#
# The fix appends a Lua `hl.config({ cursor = { no_hardware_cursors = true } })`
# block to the user's ~/.config/hypr/looknfeel.lua.
#
# nouveau only ever binds NVIDIA GPUs, so matching the driver line directly is
# enough to mean "a GPU on this machine is driven by nouveau". Skip the fix when
# nvidia.sh has just configured the proprietary driver (/etc/modprobe.d/nvidia.conf):
# those systems are still on nouveau until the first reboot, but will switch to
# the proprietary driver, which renders hardware cursors correctly.
if [[ ! -f /etc/modprobe.d/nvidia.conf ]] &&
  command -v lspci &>/dev/null &&
  LC_ALL=C lspci -k | grep -qi 'Kernel driver in use: nouveau'; then
  HYPR_LOOKNFEEL="$HOME/.config/hypr/looknfeel.lua"

  if [[ -f $HYPR_LOOKNFEEL ]] && ! grep -q 'no_hardware_cursors' "$HYPR_LOOKNFEEL"; then
    echo "Detected nouveau driver. Forcing software cursors so the mouse pointer stays visible."

    cat >>"$HYPR_LOOKNFEEL" <<'EOF'

-- nouveau does not display the hardware cursor plane on many older NVIDIA GPUs,
-- leaving the pointer invisible on the physical display. Render it in software.
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
EOF
  fi
fi
