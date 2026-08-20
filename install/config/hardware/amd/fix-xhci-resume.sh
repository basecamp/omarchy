# Opt-in: keep AMD xHCI controllers awake to avoid the broken resume path.
# Off by default to preserve laptop power draw (see basecamp/omarchy#6671).
# Enable with: omarchy toggle amd-xhci-wakeup
omarchy-toggle-enabled amd-xhci-wakeup || exit 0

if lspci -nn | grep -qE "1022:(1587|15b6|15b7|15e0|15e1|15e5|1639|148c)"; then
  echo "AMD xHCI detected (resume bug). Keeping controllers awake..."

  cat <<'EOF' | sudo tee /etc/udev/rules.d/99-omarchy-amd-xhci-wakeup.rules >/dev/null
# AMD xHCI controllers die on resume (Bugzilla 221073, Ubuntu 2158539). Keep
# them awake so the broken suspend->resume cycle never runs. Class-based match
# (PCI class 0x0c0330) covers all current and future AMD xHCI device IDs.
SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{class}=="0x0c0330", ATTR{power/control}="on", ATTR{d3cold_allowed}="0"
EOF

  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=pci --attr-match=vendor=0x1022
fi