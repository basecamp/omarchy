# Disable hardware cursors when the vmwgfx driver is in use.
#
# The VMware SVGA II DRM driver (vmwgfx) does not display the hardware cursor
# plane, leaving the mouse pointer invisible under Hyprland.

if omarchy-cmd-present lspci &&
  LC_ALL=C lspci -k | grep -qi 'Kernel driver in use: vmwgfx'; then
  looknfeel="$HOME/.config/hypr/looknfeel.lua"

  if [[ -f $looknfeel ]] && ! grep -q 'no_hardware_cursors' "$looknfeel"; then
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
