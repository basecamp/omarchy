# Display fix for Dell XPS 13 on Wildcat Lake (Xe3 iGPU).
#
# The eDP panel negotiates Panel Replay Selective Update (Early Transport)
# by default, and its sleep/wake path stalls frame updates: the panel drops
# into self-refresh between updates and wakes late, so frames are skipped in
# bursts during scrolling and animation (i915_edp_psr_status shows the source
# sitting in SLEEP). Toggling i915_edp_psr_debug at runtime confirms the
# panel is the cause. Same Xe3 pathology as the ASUS B9406 fix, on the
# Wildcat Lake generation the old Panther Lake XPS gate never matched.
#
# Both knobs are needed: xe.enable_psr=0 does not cover Panel Replay, and
# disabling only Panel Replay falls back to PSR2 selective fetch, which
# stutters the same way on this panel.

if omarchy-hw-match "XPS" && omarchy-hw-intel-wcl; then
  mkdir -p /etc/limine-entry-tool.d
  cat > /etc/limine-entry-tool.d/dell-xps-wcl-display.conf <<'EOF'
# Dell XPS (Wildcat Lake / Xe3) display workaround
KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0"
EOF
fi
