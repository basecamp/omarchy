# Intel JHL6540 Thunderbolt 3 USB xHCI (8086:15d4) on Apple laptops.
# Runtime suspend + D3cold leaves the controller asleep after unplug, so the
# next USB-C device never enumerates until xhci is rebound.
sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

if [[ $sys_vendor == Apple* ]] && lspci -nn | grep -q "8086:15d4"; then
  echo "Detected Apple Thunderbolt USB-C xHCI (8086:15d4). Keeping it awake..."

  cat <<'EOF' | sudo tee /etc/udev/rules.d/99-omarchy-apple-tb-usb-wakeup.rules >/dev/null
# Intel JHL6540 Thunderbolt 3 USB xHCI (8086:15d4)
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d4", ATTR{power/control}="on", ATTR{d3cold_allowed}="0"
EOF

  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=pci --attr-match=vendor=0x8086 --attr-match=device=0x15d4
fi
