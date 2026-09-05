# Synaptics touchpad S3 resume fix for GETAC V110G3.
#
# After S3 the i8042 controller wedges and the pad dies on both PS/2 and
# RMI4/SMBus (ENXIO); reloading psmouse or rmi_smbus does not recover it.
# i8042.nomux=1 moves the pad off the muxed AUX port onto the standard one.
# psmouse.synaptics_intertouch=1 alone does not survive S3; the two together
# do. Confirmed on V110G3 (Launchpad #2162967). Other GETAC models need their
# own confirmation.

drop_in="${OMARCHY_GETAC_V110G3_LIMINE_CONF:-/etc/limine-entry-tool.d/getac-v110g3-touchpad.conf}"

if omarchy-hw-getac-v110g3; then
  if [[ ! -f $drop_in ]] ||
    ! grep -q 'i8042.nomux=1' "$drop_in" ||
    ! grep -q 'psmouse.synaptics_intertouch=1' "$drop_in"; then
    sudo mkdir -p "$(dirname "$drop_in")"
    cat <<'EOF' | sudo tee "$drop_in" >/dev/null
# GETAC V110G3 Synaptics touchpad S3 resume
KERNEL_CMDLINE[default]+=" i8042.nomux=1 psmouse.synaptics_intertouch=1"
EOF
  fi
fi
