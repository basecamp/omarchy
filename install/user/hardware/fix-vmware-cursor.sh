# Disable hardware cursors when the vmwgfx driver is in use.
#
# The VMware SVGA II DRM driver (vmwgfx) does not display the hardware cursor
# plane, leaving the mouse pointer invisible under Hyprland.

if omarchy-cmd-present lspci &&
  LC_ALL=C lspci -k | grep -qi 'Kernel driver in use: vmwgfx'; then
  looknfeel="$HOME/.config/hypr/looknfeel.lua"

  # A comment mentioning the setting is not an assignment — vmwgfx guests
  # still have an invisible pointer until a real no_hardware_cursors = line exists.
  if [[ -f $looknfeel ]] && ! grep -Eq '^[[:space:]]*no_hardware_cursors[[:space:]]*=' "$looknfeel"; then
    echo "Detected vmwgfx driver. Forcing software cursors so the mouse pointer stays visible."

    cat >>"$looknfeel" <<'EOF'

-- VMware SVGA II (vmwgfx) does not display the hardware cursor plane,
-- leaving the pointer invisible. Render it in software.
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
EOF
  fi
fi
