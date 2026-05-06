# Display fix for ASUS ExpertBook B9406 (Panther Lake / Xe3 iGPU).
#
# Panel Replay is Xe3-new, default-on in the xe driver, and has a broken
# exit/wake path on this eDP panel: the panel latches the last-presented
# frame in self-refresh and never wakes for subsequent atomic commits, so
# the screen only updates on a full modeset (e.g. a VT switch). The older
# xe.enable_psr=0 knob does not cover Panel Replay.

if omarchy-hw-asus-expertbook-b9406; then
  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf >/dev/null
# ASUS ExpertBook B9406 (Panther Lake / Xe3) display workaround
KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"
EOF
fi
