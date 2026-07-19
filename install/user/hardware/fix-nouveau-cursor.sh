# Disable hardware cursors when the nouveau driver is in use.
#
# The nouveau DRM driver does not display the hardware cursor plane on many
# older NVIDIA GPUs, leaving the mouse pointer invisible under Hyprland.
# Skip the fix when the proprietary driver was configured: supported GPUs can
# still use nouveau during installation before switching drivers on reboot.
nvidia_config="${OMARCHY_NVIDIA_MODPROBE_CONFIG:-/etc/modprobe.d/nvidia.conf}"

if [[ ! -f $nvidia_config ]] &&
  omarchy-cmd-present lspci &&
  LC_ALL=C lspci -k | grep -qi 'Kernel driver in use: nouveau'; then
  looknfeel="$HOME/.config/hypr/looknfeel.lua"

  if [[ -f $looknfeel ]] && ! grep -q 'no_hardware_cursors' "$looknfeel"; then
    echo "Detected nouveau driver. Forcing software cursors so the mouse pointer stays visible."

    cat >>"$looknfeel" <<'EOF'

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
